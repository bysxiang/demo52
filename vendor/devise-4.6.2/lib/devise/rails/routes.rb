# frozen_string_literal: true

require "active_support/core_ext/object/try"
require "active_support/core_ext/hash/slice"

module Devise
  module RouteSet
    def finalize!
      result = super
      @devise_finalized ||= begin
        if Devise.router_name.nil? && defined?(@devise_finalized) && self != Rails.application.try(:routes)
          warn "[DEVISE] We have detected that you are using devise_for inside engine routes. " \
            "In this case, you probably want to set Devise.router_name = MOUNT_POINT, where "   \
            "MOUNT_POINT is a symbol representing where this engine will be mounted at. For "   \
            "now Devise will default the mount point to :main_app. You can explicitly set it"   \
            " to :main_app as well in case you want to keep the current behavior."
        end

        Devise.configure_warden!
        Devise.regenerate_helpers!
        true
      end
      result
    end
  end
end

module ActionDispatch::Routing
  class RouteSet #:nodoc:
    # 确保只在加载路由后才include Devise模块，因为我们需要devise_for来创建过滤器和
    # helpers。
    prepend Devise::RouteSet
  end

  class Mapper
    # 包含路由的devise_for方法。这种方法根据您在模型中定义的模块，生成devise所需的
    # 所有路由。
    #
    # ==== Examples
    #
    # 假设你已将User模型配置为使用authenticatable，confirmable和recoverable模块。在你的
    # 路由中创建此内容后:
    #
    #   devise_for :users
    #
    # 此方法将查看你的User模型并创建所需的路由:
    #
    #  # Session routes for Authenticatable (default)
    #       new_user_session GET    /users/sign_in                    {controller:"devise/sessions", action:"new"}
    #           user_session POST   /users/sign_in                    {controller:"devise/sessions", action:"create"}
    #   destroy_user_session DELETE /users/sign_out                   {controller:"devise/sessions", action:"destroy"}
    #
    #  # Password routes for Recoverable, if User model has :recoverable configured
    #      new_user_password GET    /users/password/new(.:format)     {controller:"devise/passwords", action:"new"}
    #     edit_user_password GET    /users/password/edit(.:format)    {controller:"devise/passwords", action:"edit"}
    #          user_password PUT    /users/password(.:format)         {controller:"devise/passwords", action:"update"}
    #                        POST   /users/password(.:format)         {controller:"devise/passwords", action:"create"}
    #
    #  # Confirmation routes for Confirmable, if User model has :confirmable configured
    #  new_user_confirmation GET    /users/confirmation/new(.:format) {controller:"devise/confirmations", action:"new"}
    #      user_confirmation GET    /users/confirmation(.:format)     {controller:"devise/confirmations", action:"show"}
    #                        POST   /users/confirmation(.:format)     {controller:"devise/confirmations", action:"create"}
    #
    # ==== 路由整合(Routes integration)
    #
    # devise_for意味着与其他路由方法可以很好的配合。例如，通过在命名空间内调用devise_for，
    # 它自动嵌套你的devise控制器:
    #
    #     namespace :publisher do
    #       devise_for :account
    #     end
    #
    # 上面的代码将使用publisher/sessions控制器而不是devise/sessions控制器。你可以通过级那个下面
    # 描述的:module选项传递给devise_for来直接还原更改或进行配置。
    #
    # 另请注意，使用命名空间时，它将影响控制器和视图的所有帮助程序和方法。例如，使用上面的设置，
    # 你将要使用这些方法结束: current_publisher_account, authenticate_publisher_account!,
    # publisher_account_signed_in等等。
    #
    # 路由配置唯一不影响的是模型名称。可通过:class_name选项设置模型名称。
    #
    # ==== 可选项(Options)
    #
    # 你可以使用以下选项配置路由:
    #
    #  * class_name: 如果它不能通过路由名称找到，可以设置一个不同的类以便通过devise查找。
    #
    #      devise_for :users, class_name: 'Account'
    #
    #  * path: 允许你设置将要使用的路径名，就行rails路由一样。以下路由将设置为/account而不是
    #    /users
    #
    #      devise_for :users, path: 'accounts'
    #
    #  * singular: 设置给定资源的单数名称。这用做控制器中的辅助方法(authenticate_#{singular}, 
    #    #{singular}_singned_in?, current_#{singular}和#{singular}_session)，作为路由中作用域名称和授予
    #    warden作用域。
    #
    #      devise_for :admins, singular: :manager
    #
    #      devise_scope :manager do
    #        ...
    #      end
    #
    #      class ManagerController < ApplicationController
    #        before_action authenticate_manager!
    #
    #        def show
    #          @manager = current_manager
    #          ...
    #        end
    #      end
    #
    #  * path_names: 配置不同的路径名以覆盖默认值: :sign_in, sign_out, :sign_up, :password, :confirmation,
    #    :unlock。
    #
    #      devise_for :users, path_names: {
    #        sign_in: 'login', sign_out: 'logout',
    #        password: 'secret', confirmation: 'verification',
    #        registration: 'register', edit: 'edit/profile'
    #      }
    #
    #  * controllers: 应使用的控制器。默认情况下，所有路由点使用Devise控制器。但是，如果希望它们指向自定义控制器，
    #    则应执行以下操作:
    #
    #      devise_for :users, controllers: { sessions: "users/sessions" }
    #
    #  * failure_app: 一种rack应用，在出现故障时调用。表示给定的字符串也被允许作为参数。
    #
    #  * sign_out_via: :sign_out操作接受的HTTP方法(默认为:get)。如果你希望将此限制为仅接受:post或
    #    :delete，你应该:
    #
    #      devise_for :users, sign_out_via: [:post, :delete]
    #
    #    你需要确保sign_out控件使用匹配的HTTP方法触发请求。
    #
    #  * module: 用于查找控制器的命名空间。(默认为devise，因此访问devise/session, devise/registrations等)。
    #    如果要同时命名所有命名空间,请使用模块:
    #
    #      devise_for :users, module: "users"
    #
    #  * skip: 告诉你想要跳过哪个控制器来创建路由。跳过的路由，如:sessions，不会创建此路由器。
    #    它接受 :all作为选项，意味着它根本不会生成任何路由。
    #
    #      devise_for :users, skip: :sessions
    #
    #  * only: 与:skip相反，告诉控制器只生成的路由:
    #
    #      devise_for :users, only: :sessions
    #
    #  * skip_helpers: 跳过生成Devise url helpers，如new_session_path(@user)。这对于避免与先前路由
    #    冲突很有用，默认情况下为false。它接受true作为选项，这意味着它将跳过控制器的所有helpers。通过
    #    :skip跳出指定助手，:skip_helpers指定为true。
    #
    #      devise_for :users, skip: [:registrations, :confirmations], skip_helpers: true
    #      devise_for :users, skip_helpers: [:registrations, :confirmations]
    #
    #  * format: 在生成的路由中包含(.:format)，默认为true，设置false以禁用:
    #
    #      devise_for :users, format: false
    #
    #  * constraints: 与Rails约束相同
    #
    #  * defaults: 与Rails约束相同
    #
    #  * router_name: 允许为当前范围覆盖应用程序级路由名称。
    #
    # ==== Scoping
    #
    # 在Rails3路由DSL之后，你可以在范围内嵌套devise_for调用:
    #
    #   scope "/my" do
    #     devise_for :users
    #   end
    #
    # 但是，由于Devise使用请求路径来检索当前用户，这有一点需要注意：如果你正在使用动态
    # segment，像这样...
    #
    #   scope ":locale" do
    #     devise_for :users
    #   end
    #
    # 你需要在你的ApplicationController的配置中配置default_url_options，所以Devise可以
    # 选择它:
    #
    #   class ApplicationController < ActionController::Base
    #     def self.default_url_options
    #       { locale: I18n.locale }
    #     end
    #   end
    #
    # ==== 添加自定义action以覆盖控制器(Adding custom actions to override controllers)
    #
    # 你可以将一个块传递给devise_for，它将块中定义的任何路径添加到Devise已知的actions中。如过你向控制器添加
    # 自定义操作，这一点很重要，覆盖开箱即用的Devise控制器。
    # 例子:
    #
    #    class RegistrationsController < Devise::RegistrationsController
    #      def update
    #         # do something different here
    #      end
    #
    #      def deactivate
    #        # not a standard action
    #        # deactivate code here
    #      end
    #    end
    #
    # 为了让Devise识别停用action，你的devise_scope条目应如下所示:
    #
    #     devise_scope :owner do
    #       post "deactivate", to: "registrations#deactivate", as: "deactivate_registration"
    #     end
    #
    def devise_for(*resources)
      @devise_finalized = false
      if ! Devise.secret_key
        raise_no_secret_key
      end
      options = resources.extract_options!

      options[:as]          ||= @scope[:as]     if @scope[:as].present?
      options[:module]      ||= @scope[:module] if @scope[:module].present?
      options[:path_prefix] ||= @scope[:path]   if @scope[:path].present?
      options[:path_names]    = (@scope[:path_names] || {}).merge(options[:path_names] || {})
      options[:constraints]   = (@scope[:constraints] || {}).merge(options[:constraints] || {})
      options[:defaults]      = (@scope[:defaults] || {}).merge(options[:defaults] || {})
      options[:options]       = @scope[:options] || {}
      options[:options][:format] = false if options[:format] == false

      resources.map!(&:to_sym)

      puts "输出resources"
      p resources

      resources.each do |resource|
        mapping = Devise.add_mapping(resource, options)

        begin
          if ! mapping.to.respond_to?(:devise)
            raise_no_devise_method_error!(mapping.class_name)
          end
        rescue NameError => e
          if mapping.class_name != resource.to_s.classify
            raise
          else
            warn "[WARNING] You provided devise_for #{resource.inspect} but there is " \
              "no model #{mapping.class_name} defined in your application"
            next
          end
          
        rescue NoMethodError => e
          if ! e.message.include?("undefined method `devise'")
            raise
          else
            raise_no_devise_method_error!(mapping.class_name)
          end
        end

        if options[:controllers] && options[:controllers][:omniauth_callbacks]
          if ! mapping.omniauthable?
            raise ArgumentError, "Mapping omniauth_callbacks on a resource that is not omniauthable\n" \
              "Please add `devise :omniauthable` to the `#{mapping.class_name}` model"
          end
        end

        routes = mapping.used_routes
 
        devise_scope mapping.name do
          with_devise_exclusive_scope mapping.fullpath, mapping.name, options do
            routes.each { |mod| send("devise_#{mod}", mapping, mapping.controllers) }
          end
        end
      end
    end

    # Allow you to add authentication request from the router.
    # Takes an optional scope and block to provide constraints
    # on the model instance itself.
    #
    #   authenticate do
    #     resources :post
    #   end
    #
    #   authenticate(:admin) do
    #     resources :users
    #   end
    #
    #   authenticate :user, lambda {|u| u.role == "admin"} do
    #     root to: "admin/dashboard#show", as: :user_root
    #   end
    #
    def authenticate(scope=nil, block=nil)
      constraints_for(:authenticate!, scope, block) do
        yield
      end
    end

    # Allow you to route based on whether a scope is authenticated. You
    # can optionally specify which scope and a block. The block accepts
    # a model and allows extra constraints to be done on the instance.
    #
    #   authenticated :admin do
    #     root to: 'admin/dashboard#show', as: :admin_root
    #   end
    #
    #   authenticated do
    #     root to: 'dashboard#show', as: :authenticated_root
    #   end
    #
    #   authenticated :user, lambda {|u| u.role == "admin"} do
    #     root to: "admin/dashboard#show", as: :user_root
    #   end
    #
    #   root to: 'landing#show'
    #
    def authenticated(scope=nil, block=nil)
      constraints_for(:authenticate?, scope, block) do
        yield
      end
    end

    # Allow you to route based on whether a scope is *not* authenticated.
    # You can optionally specify which scope.
    #
    #   unauthenticated do
    #     as :user do
    #       root to: 'devise/registrations#new'
    #     end
    #   end
    #
    #   root to: 'dashboard#show'
    #
    def unauthenticated(scope=nil)
      constraint = lambda do |request|
        not request.env["warden"].authenticate? scope: scope
      end

      constraints(constraint) do
        yield
      end
    end

    # 设置要在控制器中使用的devise范围。如果你有自定义路由，你需要调用此方法(也成为:as),以便
    # 指定目标控制器。
    #
    #   as :user do
    #     get "sign_in", to: "devise/sessions#new"
    #   end
    #
    # 注意，不能将两个作用域映射到同一个URL。记住，如果你视图在不指定范围的情况下访问devise
    # 控制器，它将抛出ActionNotFound异常。
    #
    # 也要注意，devise_for和as使用名词的单数形式，其他devise 路由命令使用复数形式。这将是
    # 一个好的、有效的例子。
    #
    #  devise_scope :user do
    #    get "/some/route" => "some_devise_controller"
    #  end
    #  devise_for :users
    #
    # 请注意并注意以下差异 :user和:users
    def devise_scope(scope)
      constraint = lambda do |request|
        request.env["devise.mapping"] = Devise.mappings[scope]
        true
      end

      constraints(constraint) do
        yield
      end
    end
    alias :as :devise_scope

    protected

      def devise_session(mapping, controllers) #:nodoc:
        resource :session, only: [], controller: controllers[:sessions], path: "" do
          get   :new,     path: mapping.path_names[:sign_in],  as: "new"
          post  :create,  path: mapping.path_names[:sign_in]
          match :destroy, path: mapping.path_names[:sign_out], as: "destroy", via: mapping.sign_out_via
        end
      end

      def devise_password(mapping, controllers) #:nodoc:
        resource :password, only: [:new, :create, :edit, :update],
          path: mapping.path_names[:password], controller: controllers[:passwords]
      end

      def devise_confirmation(mapping, controllers) #:nodoc:
        resource :confirmation, only: [:new, :create, :show],
          path: mapping.path_names[:confirmation], controller: controllers[:confirmations]
      end

      def devise_unlock(mapping, controllers) #:nodoc:
        if mapping.to.unlock_strategy_enabled?(:email)
          resource :unlock, only: [:new, :create, :show],
            path: mapping.path_names[:unlock], controller: controllers[:unlocks]
        end
      end

      def devise_registration(mapping, controllers) #:nodoc:
        path_names = {
          new: mapping.path_names[:sign_up],
          edit: mapping.path_names[:edit],
          cancel: mapping.path_names[:cancel]
        }

        options = {
          only: [:new, :create, :edit, :update, :destroy],
          path: mapping.path_names[:registration],
          path_names: path_names,
          controller: controllers[:registrations]
        }

        resource :registration, options do
          get :cancel
        end
      end

      def devise_omniauth_callback(mapping, controllers) #:nodoc:
        if mapping.fullpath =~ /:[a-zA-Z_]/
          raise <<-ERROR
Devise does not support scoping OmniAuth callbacks under a dynamic segment
and you have set #{mapping.fullpath.inspect}. You can work around by passing
`skip: :omniauth_callbacks` to the `devise_for` call and extract omniauth
options to another `devise_for` call outside the scope. Here is an example:

    devise_for :users, only: :omniauth_callbacks, controllers: {omniauth_callbacks: 'users/omniauth_callbacks'}

    scope '/(:locale)', locale: /ru|en/ do
      devise_for :users, skip: :omniauth_callbacks
    end
ERROR
        end
        current_scope = @scope.dup
        if @scope.respond_to? :new
          @scope = @scope.new path: nil
        else
          @scope[:path] = nil
        end
        path_prefix = Devise.omniauth_path_prefix || "/#{mapping.fullpath}/auth".squeeze("/")

        set_omniauth_path_prefix!(path_prefix)

        mapping.to.omniauth_providers.each do |provider|
          match "#{path_prefix}/#{provider}",
            to: "#{controllers[:omniauth_callbacks]}#passthru",
            as: "#{provider}_omniauth_authorize",
            via: [:get, :post]

          match "#{path_prefix}/#{provider}/callback",
            to: "#{controllers[:omniauth_callbacks]}##{provider}",
            as: "#{provider}_omniauth_callback",
            via: [:get, :post]
        end
      ensure
        @scope = current_scope
      end

      def with_devise_exclusive_scope(new_path, new_as, options) #:nodoc:
        current_scope = @scope.dup

        exclusive = { as: new_as, path: new_path, module: nil }
        exclusive.merge!(options.slice(:constraints, :defaults, :options))

        if @scope.respond_to? :new
          @scope = @scope.new exclusive
        else
          exclusive.each_pair { |key, value| @scope[key] = value }
        end
        yield
      ensure
        @scope = current_scope
      end

      def constraints_for(method_to_apply, scope=nil, block=nil)
        constraint = lambda do |request|
          request.env['warden'].send(method_to_apply, scope: scope) &&
            (block.nil? || block.call(request.env["warden"].user(scope)))
        end

        constraints(constraint) do
          yield
        end
      end

      def set_omniauth_path_prefix!(path_prefix) #:nodoc:
        if ::OmniAuth.config.path_prefix && ::OmniAuth.config.path_prefix != path_prefix
          raise "Wrong OmniAuth configuration. If you are getting this exception, it means that either:\n\n" \
            "1) You are manually setting OmniAuth.config.path_prefix and it doesn't match the Devise one\n" \
            "2) You are setting :omniauthable in more than one model\n" \
            "3) You changed your Devise routes/OmniAuth setting and haven't restarted your server"
        else
          ::OmniAuth.config.path_prefix = path_prefix
        end
      end

      def raise_no_secret_key #:nodoc:
        raise <<-ERROR
Devise.secret_key was not set. Please add the following to your Devise initializer:

  config.secret_key = '#{SecureRandom.hex(64)}'

Please ensure you restarted your application after installing Devise or setting the key.
ERROR
      end

      def raise_no_devise_method_error!(klass) #:nodoc:
        raise "#{klass} does not respond to 'devise' method. This usually means you haven't " \
          "loaded your ORM file or it's being loaded too late. To fix it, be sure to require 'devise/orm/YOUR_ORM' " \
          "inside 'config/initializers/devise.rb' or before your application definition in 'config/application.rb'"
      end
  end
end
