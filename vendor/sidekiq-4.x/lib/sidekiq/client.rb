# frozen_string_literal: true
require 'securerandom'
require 'sidekiq/middleware/chain'

module Sidekiq
  class Client

    ##
    # 定义客户端中间件：
    #
    #   client = Sidekiq::Client.new
    #   client.middleware do |chain|
    #     chain.add MyClientMiddleware
    #   end
    #   client.push('class' => 'SomeWorker', 'args' => [1,2,3])
    #
    # 所有客户端实例都默认使用全局定义的Sidekiq.client_middleware，
    # 但您可以根据需要进行更改(传递一个块，即可向这个中间件来进行删改)
    #
    def middleware(&block)
      @chain ||= Sidekiq.client_middleware
      if block_given?
        @chain = @chain.dup
        yield @chain
      end
      @chain
    end

    attr_accessor :redis_pool

    # Sidekiq::Client通常使用默认的Redis池，但是，如果你想分割你的连接池，
    # 传递一个自定义的ConnectionPool。Sidekiq作业可以跨越多个Redis实例
    # （用于可伸缩性）
    #
    #   Sidekiq::Client.new(ConnectionPool.new { Redis.new })
    # 
    # 一般来说，这只适用于非常大的Sidekiq安装处理，每秒数以千计的job。触发你不能以
    # 任何其他方式进行缩放(例如，将应用程序拆分为较小的应用程序)。
    def initialize(redis_pool=nil)
      @redis_pool = redis_pool || Thread.current[:sidekiq_via_pool] || Sidekiq.redis_pool
    end

    ##
    # 这个主方法用于将一个job推送到Redis。它接受多种选项：
    #
    #   queue - 使用的队列名称，默认为'default'
    #   class - 需要调用的Worker类
    #   args - 执行方法的简单的参数数组，必须是可JSON序列化的
    #   at - 用于schedule job的时间戳，必须为数字(例如：Time.now.to_f)
    #   retry - 如果失败，则重试此job。默认为ture或一个数字
    #   backtrace - 如果失败，是否保持回溯。默认为false
    #
    # 所有的选项必须是字符串，而不能是符号。需要你注意的是，我们正在序列化成JSON，args中的符号将会被转换为字符串。
    # 注意，+backtrace+为true会花费相当多的时间、空间在Redis。如果你不小心，大量失败的job可能会重新分配。
    #
    # 返回一个不重复的Job ID.如果中间件停止了job，将返回Nil.
    #
    # Example:
    #   push('queue' => 'my_queue', 'class' => MyWorker, 'args' => ['foo', 1, :bat => 'bar'])
    #
    def push(item)
      normed = normalize_item(item)

      # payload形如：
      # {"class"=>"Test", "args"=>[33], "retry"=>true, 
      # "queue"=>"default", "jid"=>"1586b6cd42502f4adda203de", 
      # "created_at"=>1533778530.6855056}
      payload = process_single(item['class'], normed)

      if payload
        raw_push([payload])
        payload['jid']
      end
    end

    ##
    # 推送批量作业给Redis。实践中，这种方法适用于要推送很多的作业。这种方法将会减少
    # Redis网络往返延迟。
    #
    # 采用与push相同的参数，单args是个数组。每个作业都复制所有其他键，每个作业都在客户端中间件
    # 管道中运行，每个作业都有自己的Job ID。
    #
    # Returns an array of the of pushed jobs' jids.  The number of jobs pushed can be less
    # than the number given if the middleware stopped processing for one or more jobs.
    def push_bulk(items)
      arg = items['args'].first

      if ! arg # no jobs to push
        return []
      elsif ! arg.is_a?(Array)
          raise ArgumentError, "Bulk arguments must be an Array of Arrays: [[1], [2]]"
      else

        normed = normalize_item(items)
        payloads = items['args'].map do |args|
          copy = normed.merge('args' => args, 'jid' => SecureRandom.hex(12), 'enqueued_at' => Time.now.to_f)
          result = process_single(items['class'], copy)
          result ? result : nil
        end.compact

        raw_push(payloads) if !payloads.empty?
        payloads.collect { |payload| payload['jid'] }
      end
      
    end

    # 允许跨任意数量的Redis实例分隔作业。块中定义的所有作业都将使用给定的Redis连接池。
    #
    #   pool = ConnectionPool.new { Redis.new }
    #   Sidekiq::Client.via(pool) do
    #     SomeWorker.perform_async(1,2,3)
    #     SomeOtherWorker.perform_async(1,2,3)
    #   end
    #
    # 一般来说，这只适用于非常大的Sidekiq安装处理，每秒数以千计的job。触发你不能以
    # 任何其他方式进行缩放(例如，将应用程序拆分为较小的应用程序)。
    def self.via(pool)
      if pool.nil?
        raise ArgumentError, "No pool given"
      else
        current_sidekiq_pool = Thread.current[:sidekiq_via_pool]
        if current_sidekiq_pool && current_sidekiq_pool != pool
          raise RuntimeError, "Sidekiq::Client.via is not re-entrant"
        end

        Thread.current[:sidekiq_via_pool] = pool
        yield
      end
    ensure
      Thread.current[:sidekiq_via_pool] = nil
    end

    class << self

      def push(item)
        new.push(item)
      end

      def push_bulk(items)
        new.push_bulk(items)
      end

      # 以下这个几个方法都是Resque兼容性方法。请注意所有助手都应该通过Worker#client_push
      #
      # Example usage:
      #   Sidekiq::Client.enqueue(MyWorker, 'foo', 1, :bat => 'bar')
      #
      # 消息被排入默认队列。
      #
      def enqueue(klass, *args)
        klass.client_push('class' => klass, 'args' => args)
      end

      # 示例:
      #   Sidekiq::Client.enqueue_to(:queue_name, MyWorker, 'foo', 1, :bat => 'bar')
      #
      def enqueue_to(queue, klass, *args)
        klass.client_push('queue' => queue, 'class' => klass, 'args' => args)
      end

      # 示例:
      #   Sidekiq::Client.enqueue_to_in(:queue_name, 3.minutes, MyWorker, 'foo', 1, :bat => 'bar')
      #
      def enqueue_to_in(queue, interval, klass, *args)
        int = interval.to_f
        now = Time.now.to_f
        ts = (int < 1_000_000_000 ? now + int : int)

        item = { 'class' => klass, 'args' => args, 'at' => ts, 'queue' => queue }
        item.delete('at'.freeze) if ts <= now

        klass.client_push(item)
      end

      # 示例:
      #   Sidekiq::Client.enqueue_in(3.minutes, MyWorker, 'foo', 1, :bat => 'bar')
      #
      def enqueue_in(interval, klass, *args)
        klass.perform_in(interval, *args)
      end
    end

    private

    def raw_push(payloads)
      @redis_pool.with do |conn|
        conn.multi do
          atomic_push(conn, payloads)
        end
      end
      true
    end

    def atomic_push(conn, payloads)
      if payloads.first['at']
        conn.zadd('schedule'.freeze, payloads.map do |hash|
          at = hash.delete('at'.freeze).to_s
          [at, Sidekiq.dump_json(hash)]
        end)
      else
        q = payloads.first['queue']
        now = Time.now.to_f
        to_push = payloads.map do |entry|
          entry['enqueued_at'.freeze] = now
          Sidekiq.dump_json(entry)
        end

        # q表示队列的名称，集合queues中存储着队列集合
        # queue:default 表示的是一个名为default的列表的
        # 列表
        # to_push形如：
        # ["{\"class\":\"Test\",\"args\":[33],\"retry\":true,
        # \"queue\":\"default\",\"jid\":\"d5621275db79cbb52b758d85\",
        # \"created_at\":1533778026.5115042,\"enqueued_at\":1533778026.5116568}"]

        conn.sadd('queues'.freeze, q)
        conn.lpush("queue:#{q}", to_push)
      end
    end

    def process_single(worker_class, item)
      queue = item['queue']

      x = middleware.invoke(worker_class, item, queue, @redis_pool) do
        #puts "执行这里的测试, #{item}"
        item
      end

      # puts "输出x"
      # p x

      x
    end

    def normalize_item(item)
      if ( ! item.is_a?(Hash) || (! item.has_key?('class'.freeze) || ! item.has_key?('args'.freeze)) )
        raise(ArgumentError, 
          "Job must be a Hash with 'class' and 'args' keys: { 'class' => SomeWorker, 'args' => ['bob', 1, :foo => 'bar'] }")
      end

      if ! item['args'].is_a?(Array)
        raise(ArgumentError, "Job args must be an Array")
      end

      if ! item['class'.freeze].is_a?(Class) && ! item['class'.freeze].is_a?(String)
        raise(ArgumentError, "Job class must be either a Class or String representation of the class name")
      end

      if item.has_key?('at'.freeze) && !item['at'].is_a?(Numeric)
        raise(ArgumentError, "Job 'at' must be a Numeric timestamp")
      end
      #raise(ArgumentError, "Arguments must be native JSON types, see https://github.com/mperham/sidekiq/wiki/Best-Practices") unless JSON.load(JSON.dump(item['args'])) == item['args']

      normalized_hash(item['class'.freeze])
        .each{ |key, value| item[key] = value if item[key].nil? }

      item['class'.freeze] = item['class'.freeze].to_s
      item['queue'.freeze] = item['queue'.freeze].to_s
      item['jid'.freeze] ||= SecureRandom.hex(12)
      item['created_at'.freeze] ||= Time.now.to_f
      item
    end

    def normalized_hash(item_class)
      if item_class.is_a?(Class)
        if !item_class.respond_to?('get_sidekiq_options'.freeze)
          raise(ArgumentError, "Message must include a Sidekiq::Worker class, not class name: #{item_class.ancestors.inspect}")
        end
        item_class.get_sidekiq_options
      else
        Sidekiq.default_worker_options
      end
    end
    
  end
end
