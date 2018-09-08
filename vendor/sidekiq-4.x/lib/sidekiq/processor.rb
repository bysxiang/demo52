# frozen_string_literal: true
require 'sidekiq/util'
require 'sidekiq/fetch'
require 'thread'
require 'concurrent/map'
require 'concurrent/atomic/atomic_fixnum'

module Sidekiq
  ##
  # 这个Processor是一个独立的线程，它：
  #
  # 1. 从Redis获取一个作业
  # 2. 执行作业
  #   a. 实例化Worker
  #   b. 运行中间件链
  #   c. 执行#perform方法
  #
  # 一个Processor可能因停机(processor_stopped)或作业执行过程中
  # 的错误而退出。
  #
  # 如果作业执行中发生错误，则Processor调用Manager创建一个
  # 新的Processor实例替换自己，自己将退出。
  #
  class Processor

    include Util

    attr_reader :thread
    attr_reader :job

    # @job 是UnitOfWork实例对象
    # @mgr 是Manager对象的实例，
    def initialize(mgr)
      @mgr = mgr
      @down = false
      @done = false
      @job = nil
      @thread = nil

      # puts "输出mgr.options"
      # p @mgr.options

      @strategy = (mgr.options[:fetch] || Sidekiq::BasicFetch).new(mgr.options)
      @reloader = Sidekiq.options[:reloader]
      @executor = Sidekiq.options[:executor]
    end

    # 停止线程的执行
    # param wait 是否等待线程结束
    def terminate(wait=false)
      @done = true
      if @thread && wait
        @thread.value
      end
    end

    def kill(wait=false)
      @done = true
      if !@thread
        return
      else
        # 与其他角色不同，kill不等待线程完成，因为我们不知道要花多少
        # 时间才能完成。相反，我们提供了一个`kill`方法在关闭、超时后
        # 调用。
        @thread.raise ::Sidekiq::Shutdown
        if wait
          @thread.value
        end
      end
    end

    def start
      @thread ||= safe_thread("processor", &method(:run))
    end

    private unless $TESTING

    def run
      begin
        while ! @done
          process_one
        end
        @mgr.processor_stopped(self)
      rescue Sidekiq::Shutdown
        @mgr.processor_stopped(self)
      rescue Exception => ex
        @mgr.processor_died(self, ex)
      end
    end

    def process_one
      @job = fetch

      if @job
        process(@job)
      end
      @job = nil
    end

    def get_one
      begin
        work = @strategy.retrieve_work

        # puts "输出get_one work"
        # p work

        (logger.info { "Redis is online, #{Time.now - @down} sec downtime" }; @down = nil) if @down
        work
      rescue Sidekiq::Shutdown
      rescue => ex
        handle_fetch_exception(ex)
      end
    end

    def fetch
      j = get_one
      if j && @done
        j.requeue
        nil
      else
        j
      end
    end

    def handle_fetch_exception(ex)
      if !@down
        @down = Time.now
        logger.error("Error fetching job: #{ex}")
        ex.backtrace.each do |bt|
          logger.error(bt)
        end
      end
      sleep(1)
      nil
    end

    def process(work)
      jobstr = work.job
      queue = work.queue_name

      # ack acknowledge的简写
      ack = false
      begin
        job_hash = Sidekiq.load_json(jobstr)
        @reloader.call do
          klass  = job_hash['class'.freeze].constantize
          worker = klass.new
          worker.jid = job_hash['jid'.freeze]

          # puts "输出worker"
          # p worker

          stats(worker, job_hash, queue) do
            Sidekiq::Logging.with_context(log_context(job_hash)) do
              ack = true
              Sidekiq.server_middleware.invoke(worker, job_hash, queue) do
                @executor.call do
                  # 如果我们要么尝试开始这项工作或成功完成它，那么只有ack标识它。如果中间件
                  # 在yielding之前引发异常，ack机制可以防止我们丢失作业。
                  execute_job(worker, cloned(job_hash['args'.freeze]))
                end
              end
            end
          end
          ack = true
        end #@reloader.call .. end
      rescue Sidekiq::Shutdown
        # 因为它没有在超时时间内完成，不得不强制终止作业。因为没有完成，所以
        # ack设为false。
        ack = false
      rescue Exception => ex
        handle_exception(ex, { :context => "Job raised exception", :job => job_hash, :jobstr => jobstr })
        raise
      ensure
        if ack
          work.acknowledge
        end
      end
    end

    # If we're using a wrapper class, like ActiveJob, use the "wrapped"
    # attribute to expose the underlying thing.
    def log_context(item)
      klass = item['wrapped'.freeze] || item['class'.freeze]
      "#{klass} JID-#{item['jid'.freeze]}#{" BID-#{item['bid'.freeze]}" if item['bid'.freeze]}"
    end

    def execute_job(worker, cloned_args)
      worker.perform(*cloned_args)
    end

    def thread_identity
      @str ||= Thread.current.object_id.to_s(36)
    end

    WORKER_STATE = Concurrent::Map.new
    PROCESSED = Concurrent::AtomicFixnum.new
    FAILURE = Concurrent::AtomicFixnum.new

    # 执行作业并统计
    # WORKER_STATE仅执行时存在负载记录，结束时会将其删除，这样它用来统计执行中的记录
    def stats(worker, job_hash, queue)
      tid = thread_identity
      WORKER_STATE[tid] = {:queue => queue, :payload => cloned(job_hash), :run_at => Time.now.to_i }

      # puts "输出stats"
      # p WORKER_STATE

      begin
        yield
      rescue Exception
        FAILURE.increment
        raise
      ensure
        WORKER_STATE.delete(tid)
        PROCESSED.increment
      end
    end

    # Deep clone the arguments passed to the worker so that if
    # the job fails, what is pushed back onto Redis hasn't
    # been mutated by the worker.
    def cloned(ary)
      Marshal.load(Marshal.dump(ary))
    end

  end
end
