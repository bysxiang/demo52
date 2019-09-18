# frozen_string_literal: true

require "rails/initializable"
require "active_support/inflector"
require "active_support/core_ext/module/introspection"
require "active_support/core_ext/module/delegation"

module Rails
  # Railtie是Rails框架的核心，并提供了几个钩子来扩展Rails或修改初始化过程。
  #
  # Rails的每个主要组件(Action Mailer, Action Controller, Active View, 
  # Active Record和Active Resource)都是一个Railtie。它们负责自己的初始化。这使得
  # Rails本身没有任何组件钩子，允许其他组件使用Rails默认值位置。
  #
  # 开发一个Rails扩展，并不需要任何Railtie实现，但如果你需要在Rails框架启动期间或启动
  # 之后与其进行交互，那么需要Railtie实现。
  #
  # 例如，以下扩展操作需要Railtie：
  #
  # * 创建initializers
  # * 为应用程序配置Rails框架，例如设置一个generator
  # * 向environment添加config.\*键
  # * 使用ActiveSupport::Notifications设置订阅者
  # * 添加rake任务
  #
  # == 创建一个Railtie
  #
  # 使用Railtie扩展Rails，创建一个继承的Railtie类，继承Rails::Railtie。这个类必须在Rails启动过程中加载。
  #
  # 以下示例演示了可以使用或不使用Rails的扩展：
  #
  #   # lib/my_gem/railtie.rb
  #   module MyGem
  #     class Railtie < Rails::Railtie
  #     end
  #   end
  #
  #   # lib/my_gem.rb
  #   require 'my_gem/railtie' if defined?(Rails)
  #
  # == 初始化器
  #
  # 要在Rails启动过程中添加一个Railtie初始化步骤，你只需要创建一个初始化程序块：
  #
  #   class MyRailtie < Rails::Railtie
  #     initializer "my_railtie.configure_rails_initialization" do
  #       # some initialization behavior
  #     end
  #   end
  #
  # 如果指定了参数，该块可接收application对象，你可以访问一些特定于应用程序的配置，比如中间件：
  #
  #   class MyRailtie < Rails::Railtie
  #     initializer "my_railtie.configure_rails_initialization" do |app|
  #       app.middleware.use MyRailtie::Middleware
  #     end
  #   end
  #
  # 最后，你也能够传递:before和:after选项给initializer，在这种情况下，你可能希望将其与初始化过程特定步骤相结合。
  #
  # == Configuration
  #
  # 在Railtie类内，你可以访问包含配置的配置对象，他在应用程序的所有railtie中共享。
  #
  #   class MyRailtie < Rails::Railtie
  #     # Customize the ORM
  #     config.app_generators.orm :my_railtie_orm
  #
  #     # 添加一个to_prepare块，在每个请求之前执行它。
  #     config.to_prepare do
  #       MyRailtie.setup!
  #     end
  #   end
  #
  # == 加载rake任务与生成器
  #
  # 如果你的railtie有rake任务，你可以告诉Rails通过该方法来加载它们的rake_tasks：
  #
  #   class MyRailtie < Rails::Railtie
  #     rake_tasks do
  #       load 'path/to/my_railtie.tasks'
  #     end
  #   end
  #
  # 默认情况下，Rails从你的加载路径加载生成器。但是，如果你想放置你的生成器在不同的
  # 位置，你可以在你的Railtie中指定一个块，将在正常的生成器查找期间加载它们：
  #
  #   class MyRailtie < Rails::Railtie
  #     generators do
  #       require 'path/to/my_railtie_generator'
  #     end
  #   end
  #
  # 由于加载路径上的文件名是跨gems共享的，因此请确保加载的文件有唯一的名称。
  #
  # == Application and Engine
  #
  # An engine is nothing more than a railtie with some initializers already set. And since
  # <tt>Rails::Application</tt> is an engine, the same configuration described here can be
  # used in both.
  # 一个engine不过是已经设置了一些初始化器的railtie。Rails::Application是一个引擎，这里描述的配置
  # 适用于两者。
  #
  # 请务必查看这些特定类的文档以获得更多信息。
  class Railtie
    autoload :Configuration, "rails/railtie/configuration"

    include Initializable

    ABSTRACT_RAILTIES = %w(Rails::Railtie Rails::Engine Rails::Application)

    class << self
      private :new
      delegate :config, to: :instance

      def subclasses
        @subclasses ||= []
      end

      def inherited(base)
        unless base.abstract_railtie?
          subclasses << base
        end
      end

      def rake_tasks(&blk)
        register_block_for(:rake_tasks, &blk)
      end

      def console(&blk)
        register_block_for(:load_console, &blk)
      end

      def runner(&blk)
        register_block_for(:runner, &blk)
      end

      def generators(&blk)
        register_block_for(:generators, &blk)
      end

      def abstract_railtie?
        ABSTRACT_RAILTIES.include?(name)
      end

      def railtie_name(name = nil)
        @railtie_name = name.to_s if name
        @railtie_name ||= generate_railtie_name(self.name)
      end

      # Since Rails::Railtie cannot be instantiated, any methods that call
      # +instance+ are intended to be called only on subclasses of a Railtie.
      def instance
        @instance ||= new
      end

      # Allows you to configure the railtie. This is the same method seen in
      # Railtie::Configurable, but this module is no longer required for all
      # subclasses of Railtie so we provide the class method here.
      def configure(&block)
        instance.configure(&block)
      end

      private
        def generate_railtie_name(string)
          ActiveSupport::Inflector.underscore(string).tr("/", "_")
        end

        def respond_to_missing?(name, _)
          instance.respond_to?(name) || super
        end

        # If the class method does not have a method, then send the method call
        # to the Railtie instance.
        def method_missing(name, *args, &block)
          if instance.respond_to?(name)
            instance.public_send(name, *args, &block)
          else
            super
          end
        end

        # receives an instance variable identifier, set the variable value if is
        # blank and append given block to value, which will be used later in
        # `#each_registered_block(type, &block)`
        def register_block_for(type, &blk)
          var_name = "@#{type}"
          blocks = instance_variable_defined?(var_name) ? instance_variable_get(var_name) : instance_variable_set(var_name, [])
          blocks << blk if blk
          blocks
        end
    end

    delegate :railtie_name, to: :class

    def initialize #:nodoc:
      if self.class.abstract_railtie?
        raise "#{self.class.name} is abstract, you cannot instantiate it directly."
      end
    end

    def configure(&block) #:nodoc:
      instance_eval(&block)
    end

    # This is used to create the <tt>config</tt> object on Railties, an instance of
    # Railtie::Configuration, that is used by Railties and Application to store
    # related configuration.
    def config
      @config ||= Railtie::Configuration.new
    end

    def railtie_namespace #:nodoc:
      @railtie_namespace ||= self.class.parents.detect { |n| n.respond_to?(:railtie_namespace) }
    end

    protected

      def run_console_blocks(app) #:nodoc:
        each_registered_block(:console) { |block| block.call(app) }
      end

      def run_generators_blocks(app) #:nodoc:
        each_registered_block(:generators) { |block| block.call(app) }
      end

      def run_runner_blocks(app) #:nodoc:
        each_registered_block(:runner) { |block| block.call(app) }
      end

      def run_tasks_blocks(app) #:nodoc:
        extend Rake::DSL
        each_registered_block(:rake_tasks) { |block| instance_exec(app, &block) }
      end

    private

      # run `&block` in every registered block in `#register_block_for`
      def each_registered_block(type, &block)
        klass = self.class
        while klass.respond_to?(type)
          klass.public_send(type).each(&block)
          klass = klass.superclass
        end
      end
  end
end
