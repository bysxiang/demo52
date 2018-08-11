# frozen_string_literal: true
require 'sidekiq/client'
require 'sidekiq/core_ext'

module Sidekiq

  ##
  # include这个模块，你可以轻松创建一个异步job。
  #
  # class HardWorker
  #   include Sidekiq::Worker
  #
  #   def perform(*args)
  #     # do some work
  #   end
  # end
  #
  # 然后在你的Rails应用中，你可以这样做：
  #
  #   HardWorker.perform_async(1, 2, 3)
  #
  # 请注意，perform_async是一个类方法，perform是一个实例方法。
  module Worker
    attr_accessor :jid

    def self.included(base)
      if base.ancestors.any? {|c| c.name == 'ActiveJob::Base' }
        raise ArgumentError, "You cannot include Sidekiq::Worker in an ActiveJob: #{base.name}"
      end

      base.extend(ClassMethods)
      base.class_attribute :sidekiq_options_hash
      base.class_attribute :sidekiq_retry_in_block
      base.class_attribute :sidekiq_retries_exhausted_block
    end

    def logger
      Sidekiq.logger
    end

    module ClassMethods

      def delay(*args)
        raise ArgumentError, "Do not call .delay on a Sidekiq::Worker class, call .perform_async"
      end

      def delay_for(*args)
        raise ArgumentError, "Do not call .delay_for on a Sidekiq::Worker class, call .perform_in"
      end

      def delay_until(*args)
        raise ArgumentError, "Do not call .delay_until on a Sidekiq::Worker class, call .perform_at"
      end

      def set(options)
        Thread.current[:sidekiq_worker_set] = options
        self
      end

      def perform_async(*args)
        client_push('class' => self, 'args' => args)
      end

      # +interval+必须是一个时间戳、数字或像activesupport time 时间间隔的东西
      def perform_in(interval, *args)
        int = interval.to_f
        now = Time.now.to_f
        ts = (int < 1_000_000_000 ? now + int : int)

        item = { 'class' => self, 'args' => args, 'at' => ts }

        # 优化队列，如果这个预期时间已经过去的化
        if ts <= now
          item.delete('at'.freeze)
        end

        client_push(item)
      end
      alias_method :perform_at, :perform_in

      ##
      # 允许自定义Worker的类型
      # 合法选项：
      #
      #   queue - 指定Worker的队列名称，默认为'default'
      #   retry - 为此Worker启用RetryJobs中间件，当为true时使用默认值，或指定一个整数
      #   backtrace - 是否在重试的有效负载中保存错误回溯以便在Web UI中显示，可以为true、false
      #               或保持的整数行数
      #   pool - 使用给定的Redis连接池将此类作业推送给指定的分片。
      #
      # 在实践中，允许任何选项。这是特定作业配置选项的主要机制。
      def sidekiq_options(opts={})
        self.sidekiq_options_hash = get_sidekiq_options.merge(opts.stringify_keys)
      end

      def sidekiq_retry_in(&block)
        self.sidekiq_retry_in_block = block
      end

      def sidekiq_retries_exhausted(&block)
        self.sidekiq_retries_exhausted_block = block
      end

      def get_sidekiq_options # :nodoc:
        self.sidekiq_options_hash ||= Sidekiq.default_worker_options
      end

      def client_push(item) # :nodoc:
        pool = Thread.current[:sidekiq_via_pool] || get_sidekiq_options['pool'] || Sidekiq.redis_pool
        hash = if Thread.current[:sidekiq_worker_set]
          x, Thread.current[:sidekiq_worker_set] = Thread.current[:sidekiq_worker_set], nil
          x.stringify_keys.merge(item.stringify_keys)
        else
          item.stringify_keys
        end
        Sidekiq::Client.new(pool).push(hash)
      end

    end
  end
end
