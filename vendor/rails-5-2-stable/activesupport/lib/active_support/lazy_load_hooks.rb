# frozen_string_literal: true

module ActiveSupport
  # lazy_load_hooks使Rails懒惰加地加载很多组件，从而使应用程序启动更快。由于此功能，
  # 现在没有必要在启动时require ActiveRecord::Base。而是注册了一个应用配置一次的钩子，
  # ActiveRecord::Base已加载。这里ActiveRecord::Base是用作示例，此功能也可以应用在
  # 其他地方。
  #
  # 这是一个示例，其中调用on_load方法来注册一个钩子。
  #
  #   initializer 'active_record.initialize_timezone' do
  #     ActiveSupport.on_load(:active_record) do
  #       self.time_zone_aware_attributes = true
  #       self.default_timezone = :utc
  #     end
  #   end
  #
  # When the entirety of +ActiveRecord::Base+ has been
  # evaluated then +run_load_hooks+ is invoked. The very last line of
  # +ActiveRecord::Base+ is:
  #
  #   ActiveSupport.run_load_hooks(:active_record, ActiveRecord::Base)
  #
  # 这个模块并非基于事件的。
  module LazyLoadHooks

    # @loaded 代表已经加载完毕的组件，这是执行on_load方法的化，它会执行提供的块
    # @load_hooks 
    def self.extended(base) # :nodoc:
      base.class_eval do
        @load_hooks = Hash.new { |h, k| h[k] = [] }
        @loaded     = Hash.new { |h, k| h[k] = [] }
        @run_once   = Hash.new { |h, k| h[k] = [] }
      end
    end

    # Declares a block that will be executed when a Rails component is fully
    # loaded.
    #
    # Options:
    #
    # * <tt>:yield</tt> - Yields the object that run_load_hooks to +block+.
    # * <tt>:run_once</tt> - Given +block+ will run only once.
    # 执行此方法，将会设置@load_hooks
    # 如果此时name已被加载，则会直接执行块
    def on_load(name, options = {}, &block)
      @loaded[name].each do |base|
        execute_hook(name, base, options, block)
      end

      @load_hooks[name] << [block, options]
    end

    # 执行此方法又会设置@loaded
    # 
    # 在要延迟加载的对象后来执行
    # 它在@loaded中设置已经加载的对象，base默认为Object
    # 如果之前已经调用过on_load，则它会执行on_load的块
    # 这符合此模块的设计思想
    def run_load_hooks(name, base = Object)
      @loaded[name] << base
      @load_hooks[name].each do |hook, options|
        execute_hook(name, base, options, hook)
      end
    end

    private

      # 控制块的执行，可选仅执行一次
      def with_execution_control(name, block, once)
        if ! @run_once[name].include?(block)
          if once
            @run_once[name] << block
          end

          yield
        end
      end

      # 在base对象上执行块
      # 或是将base传递给块进行调用
      def execute_hook(name, base, options, block)
        with_execution_control(name, block, options[:run_once]) do
          if options[:yield]
            block.call(base)
          else
            base.instance_eval(&block)
          end
        end
      end
  end

  extend LazyLoadHooks
end
