# encoding: utf-8
# frozen_string_literal: true
require 'sidekiq/util'
require 'sidekiq/processor'
require 'sidekiq/fetch'
require 'thread'
require 'set'

module Sidekiq

  ##
  # Manager是Sidekiq的中心协调点，控制着Processors的生命周期。
  #
  # 任务:
  #
  # 1. start: 启动Processor
  # 3. processor_died: 如果作业失败，丢弃Processor，创建新的Processor。
  # 4. quiet: 关闭空闲的Processor。
  # 5. stop: 在截止期限前彻底停止Processor。
  #
  # 请注意，只有最后一个任务（即上面的任务列表的stop）需要单独的自己的线程，因为它必须监视关闭过程。其他任务由
  # 其他线程执行。
  #
  class Manager
    include Util

    attr_reader :workers
    attr_reader :options

    # workers是Processor的集合, 根据concurrency的设置，来设置Processor的数量
    # Manager持有workers集合
    def initialize(options={})
      logger.debug { options.inspect }
      @options = options
      @count = options[:concurrency] || 25
      if @count < 1
        raise ArgumentError, "Concurrency of #{@count} is not supported"
      end

      @done = false
      @workers = Set.new
      @count.times do
        @workers << Processor.new(self)
      end
      @plock = Mutex.new
    end

    def start
      @workers.each do |x|
        x.start
      end
    end

    # 标识所有作业完成
    # 那些正在执行的将继续执行，只是我们不再关心它
    # 的返回值
    def quiet
      if ! @done
        @done = true

        logger.info { "Terminating quiet workers" }
        @workers.each { |x| x.terminate }
        fire_event(:quiet, true)
      end
    end

    # hack for quicker development / testing environment #2774
    # hack 以便在开发/测试环境中更快 #2774
    PAUSE_TIME = STDOUT.tty? ? 0.1 : 0.5

    # 阻塞性方法，在指定时间前停止所有Processor
    # 将所有作业推回到redis
    def stop(deadline)
      quiet
      fire_event(:shutdown, true)

      # 一些关闭事件可以是异步的，我们没有办法知道他们什么时候
      # 完成，但是给他们一点儿时间来生效
      sleep PAUSE_TIME
      if ! @workers.empty?
        logger.info { "Pausing to allow workers to finish..." }
        remaining = deadline - Time.now
        while remaining > PAUSE_TIME
          if @workers.empty?
            return
          end

          sleep PAUSE_TIME
          remaining = deadline - Time.now
        end
        return if @workers.empty?

        hard_shutdown
      end # if ! @workers.empty? .. end
    end

    # 停止processor，并将Processor对象从集合中删除
    def processor_stopped(processor)
      @plock.synchronize do
        @workers.delete(processor)
      end
    end

    # 停止处理
    def processor_died(processor, reason)
      @plock.synchronize do
        @workers.delete(processor)

        if ! @done
          p = Processor.new(self)
          @workers << p
          p.start
        end
      end
    end

    def stopped?
      @done
    end

    private

    def hard_shutdown
      # 超时时间已到，但workers(即Processor集合)依然在忙碌着。它们必须死，但它们的jobs将
      # 继续存在。
      cleanup = nil
      @plock.synchronize do
        cleanup = @workers.dup
      end

      if cleanup.size > 0
        jobs = cleanup.map {|p| p.job }.compact

        logger.warn { "Terminating #{cleanup.size} busy worker threads" }
        logger.warn { "Work still in progress #{jobs.inspect}" }

        # 重新排队未完成的job
        # 注意：你可能注意到我们可能会在将job推送到redis之前，workers已经终止。
        # 这是好的，因为Sidekiq规定job至少运行一次。进程终止推迟到我们确定job回到
        # Redis，因为丢一个job比再工作一次更糟糕。
        strategy = (@options[:fetch] || Sidekiq::BasicFetch)
        strategy.bulk_requeue(jobs, @options)
      end

      cleanup.each do |processor|
        processor.kill
      end
    end

  end
end
