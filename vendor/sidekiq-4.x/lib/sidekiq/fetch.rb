# frozen_string_literal: true
require 'sidekiq'

module Sidekiq
  class BasicFetch
    # 我们希望fetch操作每隔几秒超时一次，因此线程就可以检查进程是否正确关闭。
    TIMEOUT = 2

    UnitOfWork = Struct.new(:queue, :job) do
      def acknowledge
        # nothing to do
      end

      def queue_name
        queue.sub(/.*queue:/, ''.freeze)
      end

      def requeue
        Sidekiq.redis do |conn|
          conn.rpush("queue:#{queue_name}", job)
        end
      end
    end

    def initialize(options)
      @strictly_ordered_queues = !!options[:strict]
      @queues = options[:queues].map { |q| "queue:#{q}" }
      if @strictly_ordered_queues
        @queues = @queues.uniq
        @queues << TIMEOUT
      end
    end

    # 
    def retrieve_work
      # 虽然queues_cmd可包含多个键值，例如：['basic', 'bar', timeout]
      # 但是brpop方法每次只返回一个数组： [键名，值]
      cmd = queues_cmd

      work = Sidekiq.redis { |conn| conn.brpop(*cmd) }
      if work
        UnitOfWork.new(*work) # => 等效于UnitOfWork.new(work[0], work[1])
      end
    end

    # 创建Redis#brpop命令会考虑所有配置问题-配置的队列权重。默认情况下
    # Redis#brpop返回来自第一个具有待处理元素的队列数据。我们每次调用
    # Redis#brpop时都重新创建队列命令尊重权重并避免排队饥饿。
    #
    # queues 可能包含多条命令，例如：['basic', 'bar', 'bar', timeout]
    def queues_cmd
      if @strictly_ordered_queues
        @queues
      else
        queues = @queues.shuffle.uniq
        queues << TIMEOUT
        queues
      end
    end

    # 批量重新排队 从列表右侧入队
    # 通过将它作为类方法，它可以插入并有Manager来使用。使它成为一个实例方法级那个使它与接收者角色异步。
    # param igprogress 处理中的UnitOfWork实例集合
    def self.bulk_requeue(inprogress, options)
      
      if ! inprogress.empty?
        begin
          Sidekiq.logger.debug { "Re-queueing terminated jobs" }
          jobs_to_requeue = {}
          inprogress.each do |unit_of_work|
            jobs_to_requeue[unit_of_work.queue_name] ||= []
            jobs_to_requeue[unit_of_work.queue_name] << unit_of_work.job
          end

          Sidekiq.redis do |conn|
            conn.pipelined do
              jobs_to_requeue.each do |queue, jobs|
                conn.rpush("queue:#{queue}", jobs)
              end
            end
          end
          Sidekiq.logger.info("Pushed #{inprogress.size} jobs back to Redis")
        rescue => ex
          Sidekiq.logger.warn("Failed to requeue #{inprogress.size} jobs: #{ex.message}")
        end
      end
    end

  end # class BasicFetch .. end

end
