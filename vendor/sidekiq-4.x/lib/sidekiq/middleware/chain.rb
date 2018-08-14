# frozen_string_literal: true
module Sidekiq
  # 中间件处理任务前后配置的一些代码。它是一个Rack中间件。中间件
  # 存在于客户端(将作业推送到队列中)以及服务器方(当实际处理工作时)
  #
  # 向客户端添加中间件：
  #
  # Sidekiq.configure_client do |config|
  #   config.client_middleware do |chain|
  #     chain.add MyClientHook
  #   end
  # end
  #
  # 像这样修改服务端中间件：
  #
  # Sidekiq.configure_server do |config|
  #   config.server_middleware do |chain|
  #     chain.add MyServerHook
  #     chain.remove ActiveRecord
  #   end
  # end
  #
  # 紧接在另一个条目之前插入：
  #
  # Sidekiq.configure_client do |config|
  #   config.client_middleware do |chain|
  #     chain.insert_before ActiveRecord, MyClientHook
  #   end
  # end
  #
  # 紧接在一个条目之后插入：
  #
  # Sidekiq.configure_client do |config|
  #   config.client_middleware do |chain|
  #     chain.insert_after ActiveRecord, MyClientHook
  #   end
  # end
  #
  # 这是最小服务器中间件示例：
  #
  # class MyServerHook
  #   def call(worker_instance, msg, queue)
  #     puts "Before work"
  #     yield
  #     puts "After work"
  #   end
  # end
  #
  # 这是一个最小客户端中间件的例子，要注意的是方法必须返回一个结果，
  # 否则作业推送到Redis:
  #
  # class MyClientHook
  #   def call(worker_class, msg, queue, redis_pool)
  #     puts "Before push"
  #     result = yield
  #     puts "After push"
  #     result
  #   end
  # end
  #
  module Middleware
    #
    # 这个类维护一个中间件列表
    # 它提供便利、插入、删除等一些操作
    class Chain
      include Enumerable
      attr_reader :entries

      def initialize_copy(copy)
        copy.instance_variable_set(:@entries, entries.dup)
      end

      def each(&block)
        entries.each(&block)
      end

      def initialize
        @entries = []
        yield self if block_given?
      end

      def remove(klass)
        entries.delete_if { |entry| entry.klass == klass }
      end

      def add(klass, *args)
        remove(klass) if exists?(klass)
        entries << Entry.new(klass, *args)
      end

      def prepend(klass, *args)
        remove(klass) if exists?(klass)
        entries.insert(0, Entry.new(klass, *args))
      end

      def insert_before(oldklass, newklass, *args)
        i = entries.index { |entry| entry.klass == newklass }
        new_entry = i.nil? ? Entry.new(newklass, *args) : entries.delete_at(i)
        i = entries.index { |entry| entry.klass == oldklass } || 0
        entries.insert(i, new_entry)
      end

      def insert_after(oldklass, newklass, *args)
        i = entries.index { |entry| entry.klass == newklass }
        new_entry = i.nil? ? Entry.new(newklass, *args) : entries.delete_at(i)
        i = entries.index { |entry| entry.klass == oldklass } || entries.count - 1
        entries.insert(i+1, new_entry)
      end

      def exists?(klass)
        any? { |entry| entry.klass == klass }
      end

      def retrieve
        map(&:make_new)
      end

      def clear
        entries.clear
      end

      # 此方法实现不那么易懂
      # 不如Rack的实现优雅
      def invoke(*args)
        chain = retrieve.dup

        # &traverse_chain只是代表这样一个块
        # 它检查chain是否为空,为空时调用invoke方法
        # 提供的块，否则依次调用中间件集合
        # 它最终会执行到chain.empty?这里，
        # 并yield它
        traverse_chain = lambda do
          #puts "进入lambda"
          if chain.empty?
            yield
          else
          # puts "输出args else, #{args}"
            # 这里传递块
            chain.shift.call(*args, &traverse_chain)
          end
        end
        traverse_chain.call
      end
    end

    class Entry
      attr_reader :klass

      def initialize(klass, *args)
        @klass = klass
        @args  = args
      end

      def make_new
        @klass.new(*@args)
      end
    end
  end
end
