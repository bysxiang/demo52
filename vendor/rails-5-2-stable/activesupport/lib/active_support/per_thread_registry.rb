# frozen_string_literal: true

require "active_support/core_ext/module/delegation"

module ActiveSupport
  # 注意，对于最终用户代码，不推荐使用这种此方法，而使用(thread_mattr_accessor)[rdoc-ref:Module#thread_mattr_accessor]
  # 更友好。 请改用这种方法。
  #
  # 这个模块用于封装对线程局部变量的访问。
  #
  # 而不是污染线程本地命名空间
  #
  #   Thread.current[:connection_handler]
  #
  # 您定义了一个继承此模块的类
  #
  #   module ActiveRecord
  #     class RuntimeRegistry
  #       extend ActiveSupport::PerThreadRegistry
  #
  #       attr_accessor :connection_handler
  #     end
  #   end
  #
  # 并将声明的实例方法访问器作为类方法调用。所以：
  #
  #   ActiveRecord::RuntimeRegistry.connection_handler = connection_handler
  #
  # 设置当前线程的本地连接处理程序，和
  #
  #   ActiveRecord::RuntimeRegistry.connection_handler
  #
  # 返回当前线程的本地连接处理程序
  #
  # This feature is accomplished by instantiating the class and storing the
  # instance as a thread local keyed by the class name. In the example above
  # a key "ActiveRecord::RuntimeRegistry" is stored in <tt>Thread.current</tt>.
  # The class methods proxy to said thread local instance.
  #
  # 该特性通过实例化类和存储实例的类名在线程本地存储中。在上面的例子中，一个键
  # "ActiveRecord::RuntimeRegistry"存储在Thread.current中。类方法代理到上述线程
  # 本地实例。
  #
  # 如果类有初始化器，它必须不接受参数。
  #
  # 备注，它在每个继承此模块的类上，将实例方法代理为类方法，将其存储Thread.current中
  # 这个类实现了instance方法，它使类的实例存储与TLS上，并且会代理实例类方法的访问
  # (实例方法同时成为类方法)。
  module PerThreadRegistry
    def self.extended(object)
      object.instance_variable_set "@per_thread_registry_key", object.name.freeze
    end

    def instance
      puts "进入instance"
      Thread.current[@per_thread_registry_key] ||= new
    end

    private
      def method_missing(name, *args, &block)
        puts "进入miss"
        # 将方法定义缓存接收器的单例方法。
        #
        # 通过#delegate来处理它，我们避免捕获参数。
        singleton_class.delegate name, to: :instance

        puts "代理完毕, #{self}"

        send(name, *args, &block)
      end
  end
end
