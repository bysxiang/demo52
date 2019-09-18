# frozen_string_literal: true

require "rails/railtie"
require "rails/engine/railties"
require "active_support/core_ext/module/delegation"
require "pathname"
require "thread"

module Rails
  # Rails::Engine允许你包装指定的Rails应用或子集功能，并与其他应用程序共享。Rails3.0之后，
  # 每一个Rails::Application只是一个引擎，它允许简单功能和应用程序共享。
  #
  # 任何Rails::Engine也是一个Rails::Railtie，所以相同的方法(如rake_tasks和generator)和配置可用于任何继承于Railtie的类。
  #
  # == 创建一个引擎
  #
  # 如果你想要一个gem作为引擎，你必须在里面指定一个一个Engine，你的插件 lib目录(类似于我们如何制定一个Railtie)：
  #
  #   # lib/my_engine.rb
  #   module MyEngine
  #     class Engine < Rails::Engine
  #     end
  #   end
  #
  # 然后确保该文件在你的config/application.rb的顶部加载(或你的Gemfile中),它将自动加载模型，控制器和帮助，在app里面
  # 加载config/routes.rb，加载config/locales/*，并在lib/tasks/*加载任务。
  #
  # == Configuration
  #
  # 除了在整个应用程序中共享的Railtie配置外，在Rails::Engine你可以访问autoload_paths, eager_load_paths和
  # autoload_once_paths，与Railtie不同，它们的范围是当前引擎。
  #
  #   class MyEngine < Rails::Engine
  #     添加一条加载路径到这个引擎
  #     config.autoload_paths << File.expand_path("lib/some/path", __dir__)
  #
  #     initializer "my_engine.add_middleware" do |app|
  #       app.middleware.use MyEngine::Middleware
  #     end
  #   end
  #
  # == Generators
  #
  # 你可以通过config.generators设置生成器：
  #
  #   class MyEngine < Rails::Engine
  #     config.generators do |g|
  #       g.orm             :active_record
  #       g.template_engine :erb
  #       g.test_framework  :test_unit
  #     end
  #   end
  #
  # 你还可以使用config.app_generators为应用程序设置生成器：:
  #
  #   class MyEngine < Rails::Engine
  #     # 请注意，您也可以级那个块传递给app_generators，方法与将其传递给generators方法
  #     # 相同
  #     config.app_generators.orm :datamapper
  #   end
  #
  # == Paths
  #
  # 应用程序和引擎具有更灵活的路径配置(与前面的硬编码路径配置相反)。这意味着你不需要将控制器
  # 放在app/controllers内，你可以放置在任意你觉得方便的地方。
  #
  # 例如，假设你想要将控制器放置在lib/controllers中，你可以把它设置为一个选项：
  #
  #   class MyEngine < Rails::Engine
  #     paths["app/controllers"] = "lib/controllers"
  #   end
  #
  # 你还可以让你的控制器同时从app/controllers和lib/controllers两个地方加载：
  #
  #   class MyEngine < Rails::Engine
  #     paths["app/controllers"] << "lib/controllers"
  #   end
  #
  # 引擎的可用路径：
  #
  #   class MyEngine < Rails::Engine
  #     paths["app"]                 # => ["app"]
  #     paths["app/controllers"]     # => ["app/controllers"]
  #     paths["app/helpers"]         # => ["app/helpers"]
  #     paths["app/models"]          # => ["app/models"]
  #     paths["app/views"]           # => ["app/views"]
  #     paths["lib"]                 # => ["lib"]
  #     paths["lib/tasks"]           # => ["lib/tasks"]
  #     paths["config"]              # => ["config"]
  #     paths["config/initializers"] # => ["config/initializers"]
  #     paths["config/locales"]      # => ["config/locales"]
  #     paths["config/routes.rb"]    # => ["config/routes.rb"]
  #   end
  #
  # Application类为此集合添加了更多路径。在你的应用程序中，app内所有文件夹都自动添加到了加载路径
  # 中。例如，如果您有一个app/services文件中，它将默认添加。
  #
  # == Endpoint
  #
  # 所有引擎同样也是一个Rack应用。如果你有一个Rack程序，那会很有用。你希望使用Engine包装，并提供一些引擎功能。
  #
  # 要做到这一点，使用endpoint方法：
  #
  #   module MyEngine
  #     class Engine < Rails::Engine
  #       endpoint MyRackApplication
  #     end
  #   end
  #
  # 现在，你可以将引擎安装在应用程序的路由中：
  #
  #   Rails.application.routes.draw do
  #     mount MyEngine::Engine => "/engine"
  #   end
  #
  # == Middleware stack
  #
  # 作为引擎现在可以成为一个Rack endpoint，它也可以有一个中间件堆栈。用法与Aplication相同：
  #
  #   module MyEngine
  #     class Engine < Rails::Engine
  #       middleware.use SomeMiddleware
  #     end
  #   end
  #
  # == Routes
  #
  # 如果不指定端点，则将使用路由作为默认值端点。你可以像使用应用程序的路由一样使用它们：
  #
  #   # ENGINE/config/routes.rb
  #   MyEngine::Engine.routes.draw do
  #     get "/" => "posts#index"
  #   end
  #
  # == Mount priority
  #
  # 请注意，你的应用程序现在又多个路由器，最好避免通过许多路由器传递请求。考虑这种情况：
  #
  #   Rails.application.routes.draw do
  #     mount MyEngine::Engine => "/blog"
  #     get "/blog/omg" => "main#omg"
  #   end
  #
  # MyEngine mount在/blog，/blog/omg指向application的控制器。在这种情况下，对/blog/omg的请求将通过
  # MyEngine处理，如果在Engine的路由没有这样的配置，它将被分派到main/omg。交换它们更好：
  #
  #   Rails.application.routes.draw do
  #     get "/blog/omg" => "main#omg"
  #     mount MyEngine::Engine => "/blog"
  #   end
  #
  # 现在，Engine只会获得Application未处理的请求
  #
  # == Engine name
  #
  # 有一些地方使用引擎的名字：
  #
  # * 路由： 当你使用mount (MyEngine::Engine => '/my_engine')安装Engine时，它被当作默认值 ：as选项
  # * 一些rake任务基于引擎名称。例如my_engine:install::migrations， my_engine:install:assets
  #
  # 引擎名称默认设置为基于类名，对于MyEngine::Engine它将是my_engine_engine。你可以使用engine_name方法
  # 手动更改它
  #
  #   module MyEngine
  #     class Engine < Rails::Engine
  #       engine_name "my_engine"
  #     end
  #   end
  #
  # == Isolated Engine
  #
  # 通常，当您在引擎中创建控制器、助手和模型时，会对它们进行处理就好像它们是在应用程序内部创建的一样。
  # 这意味着所有的帮手和应用程序中的命名路由也将对引擎的控制器可用。
  #
  # 然而，有时您希望将引擎与应用程序隔离，特别是如果您的引擎有自己的路由器。为此，只需调用isolate_namespace。此
  # 方法需要你传递一个模块，在该模块内，您所有的控制器、辅助程序及模型均应嵌套至：
  #
  #   module MyEngine
  #     class Engine < Rails::Engine
  #       isolate_namespace MyEngine
  #     end
  #   end
  #
  # 这样，+MyEngine+模块内的所有内容将被隔离。
  #
  # 考虑这样的控制器：
  #
  #   module MyEngine
  #     class FooController < ActionController::Base
  #     end
  #   end
  #
  # 如果一个引擎被标记为孤立的，+FooController+只能访问来自+Engine+的助手和来自MyEngine::Engine.routes
  # 的url_helpers.
  #
  # 隔离引擎的下一个变化时路由行为。通常，在为控制器指定命名空间时，还需要为路由指定
  # 命名空间。对于隔离引擎，引擎的命名空间时自动应用的，因此您不需要在您的路由中指定它：
  #
  #   MyEngine::Engine.routes.draw do
  #     resources :articles
  #   end
  #
  # 如果MyEngine是隔离的，上面的路由将自动指向MyEngine::ApplicationController。而且，你不必使
  # 用更长的 url 帮助方法，如my_engine_articles_path。相反，你应该简单的使用articles_path，
  # 与你的应用中一样。
  #
  # 为了使这种行为与框架的其他部分保持一致，一个孤立的引擎也会影响ActiveModel::Naming。当你使用
  # 一个命名空间模型时，例如MyEngine::Article，它通常会使用前缀"my_engine"，在一个隔离引擎中，
  # 为方便表单自动，url 帮助方法中前缀会被省略。
  #
  #   polymorphic_url(MyEngine::Article.new)
  #   # => "articles_path" # not "my_engine_articles_path"
  #
  #   form_for(MyEngine::Article.new) do
  #     text_field :title # => <input type="text" name="article[title]" id="article_title" />
  #   end
  #
  # 另外，一个隔离引擎会根据命名空间来设置它的名字，所以，MyEngine::Engine.engine_name将为
  # 'my_engine'。它也将设置MyEngine.table_name_prefix为"my_engine_"，将MyEngine::Aritle更改为
  # 使用my_engine_articles表。
  #
  # == 在引擎外使用引擎路由
  #
  # 由于现在可以在应用程序的路由中安装一个引擎，所以无法在应用程序的内部直接访问+Engine+的url_helpers。
  # 当你在应用程序的路由中安装一个引擎时，一个特殊的助手可以让你做到这一点。考虑这样一个场景：
  #
  #   # config/routes.rb
  #   Rails.application.routes.draw do
  #     mount MyEngine::Engine => "/my_engine", as: "my_engine"
  #     get "/foo" => "foo#index"
  #   end
  #
  # 现在，你可以使用my_engine帮助方法在你的应用中：
  #
  #   class FooController < ApplicationController
  #     def index
  #       my_engine.root_url # => /my_engine/
  #     end
  #   end
  #
  # 还有一个main_app帮助器，你可以访问Engine中的应用程序路由：
  #
  #   module MyEngine
  #     class BarController
  #       def index
  #         main_app.foo_path # => /foo
  #       end
  #     end
  #   end
  #
  # 请注意，提供给:as选项将engine_name设置为默认值，所以大部分时间，你可以省略它。
  #
  # 最后，如果要使用引擎的路由polymorhpic_url生成一个url,你还需要传递引擎助手。
  # 让我们说你想要创建一个指向一个引擎路由的表单。所以你需要做的是把帮助者作为数组中的
  # 第一个元素网址属性：
  #
  #   form_for([my_engine, @user])
  #
  # 此代码将使用my_engine.user_path(@user)生成正确的路由。
  #
  # == 隔离引擎的帮助器(Isolated engine's helpers)
  #
  # 有时您可能想要隔离引擎，但使用为其定义的帮助程序。如果您想要共享一些特定的帮助程序，可以将其
  # 添加到你应用的ApplicationController中:
  #
  #   class ApplicationController < ActionController::Base
  #     helper MyEngine::SharedEngineHelper
  #   end
  #
  # 如果你想要包括所有引擎的助手，可以在引擎上使用#helper方法：
  #
  #   class ApplicationController < ActionController::Base
  #     helper MyEngine::Engine.helpers
  #   end
  #
  # It will include all of the helpers from engine's directory. Take into account that this does
  # not include helpers defined in controllers with helper_method or other similar solutions,
  # only helpers defined in the helpers directory will be included.
  # 它将包含engine目录中所有的helpers程序。考虑到这一点，不包括helper_method或其他类似解决方案的控制器中
  # 定义的helpers，只包括在helper目录中定义的程序。
  #
  # == 迁移与种子数据(Migrations & seed data)
  #
  # 引擎可以拥有自己的迁移。默认路径在应用程序中：db/migrate
  #
  # 要在应用程序中使用引擎的迁移，你可以使用rake任务，将它们复制到应用程序的目录：
  #
  #   rake ENGINE_NAME:install:migrations
  #
  # 注意，如果应用中已存在同名迁移，则可能会跳过某些迁移。在这种情况下，您必须决定是保留迁移还是重命名在应用程序
  # 中迁移并重新复制迁移。
  #
  # 如果你的引擎有迁移，你可能还行为数据库准备种子数据 seeds.rb。你可以使用load_seed方法来加载这些数据。
  #
  #   MyEngine::Engine.load_seed
  #
  # == (加载优先级)Loading priority
  #
  # 为了更改引擎的优先级，你可以在主应用程序中使用config.railties_order。这将影响加载视图，帮助程序，
  # assets和所有其他文件的优先级，涉及引擎或应用程序。
  #
  #   # load Blog::Engine with highest priority, followed by application and other railties
  #   config.railties_order = [Blog::Engine, :main_app, :all]
  class Engine < Railtie
    autoload :Configuration, "rails/engine/configuration"

    class << self
      attr_accessor :called_from, :isolated

      alias :isolated? :isolated
      alias :engine_name :railtie_name

      delegate :eager_load!, to: :instance

      def inherited(base)
        unless base.abstract_railtie?
          Rails::Railtie::Configuration.eager_load_namespaces << base

          base.called_from = begin
            call_stack = caller_locations.map { |l| l.absolute_path || l.path }

            File.dirname(call_stack.detect { |p| p !~ %r[railties[\w.-]*/lib/rails|rack[\w.-]*/lib/rack] })
          end
        end

        super
      end

      def find_root(from)
        find_root_with_flag "lib", from
      end

      def endpoint(endpoint = nil)
        @endpoint ||= nil
        @endpoint = endpoint if endpoint
        @endpoint
      end

      def isolate_namespace(mod)
        engine_name(generate_railtie_name(mod.name))

        routes.default_scope = { module: ActiveSupport::Inflector.underscore(mod.name) }
        self.isolated = true

        unless mod.respond_to?(:railtie_namespace)
          name, railtie = engine_name, self

          mod.singleton_class.instance_eval do
            define_method(:railtie_namespace) { railtie }

            unless mod.respond_to?(:table_name_prefix)
              define_method(:table_name_prefix) { "#{name}_" }
            end

            unless mod.respond_to?(:use_relative_model_naming?)
              class_eval "def use_relative_model_naming?; true; end", __FILE__, __LINE__
            end

            unless mod.respond_to?(:railtie_helpers_paths)
              define_method(:railtie_helpers_paths) { railtie.helpers_paths }
            end

            unless mod.respond_to?(:railtie_routes_url_helpers)
              define_method(:railtie_routes_url_helpers) { |include_path_helpers = true| railtie.routes.url_helpers(include_path_helpers) }
            end
          end
        end
      end

      # Finds engine with given path.
      def find(path)
        expanded_path = File.expand_path path
        Rails::Engine.subclasses.each do |klass|
          engine = klass.instance
          return engine if File.expand_path(engine.root) == expanded_path
        end
        nil
      end
    end

    delegate :middleware, :root, :paths, to: :config
    delegate :engine_name, :isolated?, to: :class

    def initialize
      @_all_autoload_paths = nil
      @_all_load_paths     = nil
      @app                 = nil
      @config              = nil
      @env_config          = nil
      @helpers             = nil
      @routes              = nil
      @app_build_lock      = Mutex.new
      super
    end

    # Load console and invoke the registered hooks.
    # Check <tt>Rails::Railtie.console</tt> for more info.
    def load_console(app = self)
      require "rails/console/app"
      require "rails/console/helpers"
      run_console_blocks(app)
      self
    end

    # Load Rails runner and invoke the registered hooks.
    # Check <tt>Rails::Railtie.runner</tt> for more info.
    def load_runner(app = self)
      run_runner_blocks(app)
      self
    end

    # Load Rake, railties tasks and invoke the registered hooks.
    # Check <tt>Rails::Railtie.rake_tasks</tt> for more info.
    def load_tasks(app = self)
      require "rake"
      run_tasks_blocks(app)
      self
    end

    # Load Rails generators and invoke the registered hooks.
    # Check <tt>Rails::Railtie.generators</tt> for more info.
    def load_generators(app = self)
      require "rails/generators"
      run_generators_blocks(app)
      Rails::Generators.configure!(app.config.generators)
      self
    end

    # Eager load the application by loading all ruby
    # files inside eager_load paths.
    def eager_load!
      config.eager_load_paths.each do |load_path|
        matcher = /\A#{Regexp.escape(load_path.to_s)}\/(.*)\.rb\Z/
        Dir.glob("#{load_path}/**/*.rb").sort.each do |file|
          require_dependency file.sub(matcher, '\1')
        end
      end
    end

    def railties
      @railties ||= Railties.new
    end

    # Returns a module with all the helpers defined for the engine.
    def helpers
      @helpers ||= begin
        helpers = Module.new
        all = ActionController::Base.all_helpers_from_path(helpers_paths)
        ActionController::Base.modules_for_helpers(all).each do |mod|
          helpers.include(mod)
        end
        helpers
      end
    end

    # Returns all registered helpers paths.
    def helpers_paths
      paths["app/helpers"].existent
    end

    # Returns the underlying Rack application for this engine.
    def app
      @app || @app_build_lock.synchronize {
        @app ||= begin
          stack = default_middleware_stack
          config.middleware = build_middleware.merge_into(stack)
          config.middleware.build(endpoint)
        end
      }
    end

    # Returns the endpoint for this engine. If none is registered,
    # defaults to an ActionDispatch::Routing::RouteSet.
    def endpoint
      self.class.endpoint || routes
    end

    # Define the Rack API for this engine.
    def call(env)
      req = build_request env
      app.call req.env
    end

    # Defines additional Rack env configuration that is added on each call.
    def env_config
      @env_config ||= {}
    end

    # Defines the routes for this engine. If a block is given to
    # routes, it is appended to the engine.
    def routes
      @routes ||= ActionDispatch::Routing::RouteSet.new_with_config(config)
      @routes.append(&Proc.new) if block_given?
      @routes
    end

    # Define the configuration object for the engine.
    def config
      @config ||= Engine::Configuration.new(self.class.find_root(self.class.called_from))
    end

    # Load data from db/seeds.rb file. It can be used in to load engines'
    # seeds, e.g.:
    #
    # Blog::Engine.load_seed
    def load_seed
      seed_file = paths["db/seeds.rb"].existent.first
      load(seed_file) if seed_file
    end

    # Add configured load paths to Ruby's load path, and remove duplicate entries.
    # 
    # 将load_path, autoload_path, eager_load_path等加入$LOAD_PATH中
    initializer :set_load_path, before: :bootstrap_hook do
      _all_load_paths.reverse_each do |path|
        $LOAD_PATH.unshift(path) if File.directory?(path)
      end
      $LOAD_PATH.uniq!
    end

    # Set the paths from which Rails will automatically load source files,
    # and the load_once paths.
    #
    # This needs to be an initializer, since it needs to run once
    # per engine and get the engine as a block parameter.
    #
    # 将自动加载路径添加到Dependencies类的autoload_paths中
    initializer :set_autoload_paths, before: :bootstrap_hook do
      ActiveSupport::Dependencies.autoload_paths.unshift(*_all_autoload_paths)
      ActiveSupport::Dependencies.autoload_once_paths.unshift(*_all_autoload_once_paths)

      # Freeze so future modifications will fail rather than do nothing mysteriously
      config.autoload_paths.freeze
      config.eager_load_paths.freeze
      config.autoload_once_paths.freeze
    end

    initializer :add_routing_paths do |app|
      routing_paths = paths["config/routes.rb"].existent

      if routes? || routing_paths.any?
        app.routes_reloader.paths.unshift(*routing_paths)
        app.routes_reloader.route_sets << routes
      end
    end

    # I18n load paths are a special case since the ones added
    # later have higher priority.
    initializer :add_locales do
      config.i18n.railties_load_path << paths["config/locales"]
    end

    initializer :add_view_paths do
      views = paths["app/views"].existent
      unless views.empty?
        ActiveSupport.on_load(:action_controller) { prepend_view_path(views) if respond_to?(:prepend_view_path) }
        ActiveSupport.on_load(:action_mailer) { prepend_view_path(views) }
      end
    end

    # 加载环境配置信息
    initializer :load_environment_config, before: :load_environment_hook, group: :all do
      paths["config/environments"].existent.each do |environment|
        require environment
      end
    end

    initializer :prepend_helpers_path do |app|
      if !isolated? || (app == self)
        app.config.helpers_paths.unshift(*paths["app/helpers"].existent)
      end
    end

    # load initializers目录下的初始化脚本
    initializer :load_config_initializers do
      config.paths["config/initializers"].existent.sort.each do |initializer|
        load_config_initializer(initializer)
      end
    end

    initializer :engines_blank_point do
      # We need this initializer so all extra initializers added in engines are
      # consistently executed after all the initializers above across all engines.
    end

    rake_tasks do
      next if is_a?(Rails::Application)
      next unless has_migrations?

      namespace railtie_name do
        namespace :install do
          desc "Copy migrations from #{railtie_name} to application"
          task :migrations do
            ENV["FROM"] = railtie_name
            if Rake::Task.task_defined?("railties:install:migrations")
              Rake::Task["railties:install:migrations"].invoke
            else
              Rake::Task["app:railties:install:migrations"].invoke
            end
          end
        end
      end
    end

    def routes? #:nodoc:
      @routes
    end

    protected

      def run_tasks_blocks(*) #:nodoc:
        super
        paths["lib/tasks"].existent.sort.each { |ext| load(ext) }
      end

    private

      def load_config_initializer(initializer) # :doc:
        ActiveSupport::Notifications.instrument("load_config_initializer.railties", initializer: initializer) do
          load(initializer)
        end
      end

      def has_migrations?
        paths["db/migrate"].existent.any?
      end

      def self.find_root_with_flag(flag, root_path, default = nil) #:nodoc:
        while root_path && File.directory?(root_path) && !File.exist?("#{root_path}/#{flag}")
          parent = File.dirname(root_path)
          root_path = parent != root_path && parent
        end

        root = File.exist?("#{root_path}/#{flag}") ? root_path : default
        raise "Could not find root path for #{self}" unless root

        Pathname.new File.realpath root
      end

      def default_middleware_stack
        ActionDispatch::MiddlewareStack.new
      end

      def _all_autoload_once_paths
        config.autoload_once_paths
      end

      def _all_autoload_paths
        @_all_autoload_paths ||= (config.autoload_paths + config.eager_load_paths + config.autoload_once_paths).uniq
      end

      def _all_load_paths
        @_all_load_paths ||= (config.paths.load_paths + _all_autoload_paths).uniq
      end

      def build_request(env)
        env.merge!(env_config)
        req = ActionDispatch::Request.new env
        req.routes = routes
        req.engine_script_name = req.script_name
        req
      end

      def build_middleware
        config.middleware
      end
  end
end
