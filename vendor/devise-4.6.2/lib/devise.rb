# frozen_string_literal: true

require 'rails'
require 'active_support/core_ext/numeric/time'
require 'active_support/dependencies'
require 'orm_adapter'
require 'set'
require 'securerandom'
require 'responders'

module Devise
  autoload :Delegator,          'devise/delegator'
  autoload :Encryptor,          'devise/encryptor'
  autoload :FailureApp,         'devise/failure_app'
  autoload :OmniAuth,           'devise/omniauth'
  autoload :ParameterFilter,    'devise/parameter_filter'
  autoload :ParameterSanitizer, 'devise/parameter_sanitizer'
  autoload :TestHelpers,        'devise/test_helpers'
  autoload :TimeInflector,      'devise/time_inflector'
  autoload :TokenGenerator,     'devise/token_generator'
  autoload :SecretKeyFinder,    'devise/secret_key_finder'

  module Controllers
    autoload :Helpers,        'devise/controllers/helpers'
    autoload :Rememberable,   'devise/controllers/rememberable'
    autoload :ScopedViews,    'devise/controllers/scoped_views'
    autoload :SignInOut,      'devise/controllers/sign_in_out'
    autoload :StoreLocation,  'devise/controllers/store_location'
    autoload :UrlHelpers,     'devise/controllers/url_helpers'
  end

  module Hooks
    autoload :Proxy, 'devise/hooks/proxy'
  end

  module Mailers
    autoload :Helpers, 'devise/mailers/helpers'
  end

  module Strategies
    autoload :Base,            'devise/strategies/base'
    autoload :Authenticatable, 'devise/strategies/authenticatable'
  end

  module Test
    autoload :ControllerHelpers,  'devise/test/controller_helpers'
    autoload :IntegrationHelpers, 'devise/test/integration_helpers'
  end

  # 包含devise扩展配置的常量。不应该被用户修改(这就是为什么它们是常量)。
  ALL         = []
  CONTROLLERS = {}
  ROUTES      = {}
  STRATEGIES  = {}
  URL_HELPERS = {}

  # 不需要用户输入的策略。
  NO_INPUT = []

  # 用于检测参数的为真的值
  TRUE_VALUES = [true, 1, '1', 't', 'T', 'true', 'TRUE']

  # 密钥生成器使用的密钥
  mattr_accessor :secret_key
  @@secret_key = nil

  # cookie的自定义域或密钥。默认情况下未设置
  mattr_accessor :rememberable_options
  @@rememberable_options = {}

  # hash密码的次数。
  mattr_accessor :stretches
  @@stretches = 11

  # 通过http身份验证进行身份认证时使用的默认密钥。
  mattr_accessor :http_authentication_key
  @@http_authentication_key = nil

  # 验证用户时使用的密钥
  mattr_accessor :authentication_keys
  @@authentication_keys = [:email]

  # 验证用户身份时使用的请求密钥。
  mattr_accessor :request_keys
  @@request_keys = []

  # 应该不区分大小写的键。
  mattr_accessor :case_insensitive_keys
  @@case_insensitive_keys = [:email]

  # 应该删除空格的键
  mattr_accessor :strip_whitespace_keys
  @@strip_whitespace_keys = [:email]

  # 如果默认启用http身份验证。
  mattr_accessor :http_authenticatable
  @@http_authenticatable = false

  # 如果应该为ajax请求返回http头。默认为true.
  mattr_accessor :http_authenticatable_on_xhr
  @@http_authenticatable_on_xhr = true

  # 如果默认情况下启用了params身份验证。
  mattr_accessor :params_authenticatable
  @@params_authenticatable = true

  # http基本身份验证中使用的领域。
  mattr_accessor :http_authentication_realm
  @@http_authentication_realm = "Application"

  # 用于验证电子邮件的正则表达式。它断言没有@符号或域中的空白，等等。有一个@符号分割
  # localpart和域。
  mattr_accessor :email_regexp
  @@email_regexp = /\A[^@\s]+@[^@\s]+\z/

  # 范围验证密码的长度。
  mattr_accessor :password_length
  @@password_length = 6..128

  # 无需再次请求凭证即可记住用户的时间。
  mattr_accessor :remember_for
  @@remember_for = 2.weeks

  # 如果为true，则在通过cookie记住时延长用户的记忆期。
  mattr_accessor :extend_remember_period
  @@extend_remember_period = false

  # 如果为true，那么当用户退出时，所有记住我的令牌都将失效。
  mattr_accessor :expire_all_remember_me_on_sign_out
  @@expire_all_remember_me_on_sign_out = true

  # 在确认账户之前，您可以访问账户的时间间隔。nil - 允许无限制访问无限时间
  mattr_accessor :allow_unconfirmed_access_for
  @@allow_unconfirmed_access_for = 0.days

  # 确认令牌的有效的时间间隔。nil = 无限制。
  mattr_accessor :confirm_within
  @@confirm_within = nil

  # 定义确认账户时将使用的密钥。
  mattr_accessor :confirmation_keys
  @@confirmation_keys = [:email]

  # 定义电子邮件是否应该可重新启动。
  mattr_accessor :reconfirmable
  @@reconfirmable = true

  # 没有活动的用户会话超时的时间间隔。
  mattr_accessor :timeout_in
  @@timeout_in = 30.minutes

  # 用于hash密码。请使用rails secret生成。
  mattr_accessor :pepper
  @@pepper = nil

  # 用于在更改电子邮件时向原始用户电子邮件发送通知。
  mattr_accessor :send_email_changed_notification
  @@send_email_changed_notification = false

  # 用于在密码更改时向用户发送通知。
  mattr_accessor :send_password_change_notification
  @@send_password_change_notification = false

  # 范围视图。因为它依赖于回退来呈现默认视图，所以它是默认关闭。
  mattr_accessor :scoped_views
  @@scoped_views = false

  # 定义可用于锁定账户的策略。
  # 值：:failed_attempts, :none。
  mattr_accessor :lock_strategy
  @@lock_strategy = :failed_attempts

  # 定义锁定和解锁账户时使用的key
  mattr_accessor :unlock_keys
  @@unlock_keys = [:email]

  # 定义可用于解锁账户的策略。
  # 值: :email, :time, :both
  mattr_accessor :unlock_strategy
  @@unlock_strategy = :both

  # 锁定账户之前的身份验证尝试次数
  mattr_accessor :maximum_attempts
  @@maximum_attempts = 20

  # 如果:time被定义为unlock_strategy，则解锁帐户的时间间隔
  mattr_accessor :unlock_in
  @@unlock_in = 1.hour

  # 定义在恢复密码时将使用的key。
  mattr_accessor :reset_password_keys
  @@reset_password_keys = [:email]

  # 您可以使用重置密码key重置密码的时间间隔。
  mattr_accessor :reset_password_within
  @@reset_password_within = 6.hours

  # 设置为false时，重置密码不会自动登陆用户。
  mattr_accessor :sign_in_after_reset_password
  @@sign_in_after_reset_password = true

  # warden使用的default scope
  mattr_accessor :default_scope
  @@default_scope = nil

  # 发送Devise邮件的地址。
  mattr_accessor :mailer_sender
  @@mailer_sender = nil

  # 跳过会话存储以执行以下策略
  mattr_accessor :skip_session_storage
  @@skip_session_storage = [:http_auth]

  # 应将哪些格式视为导航。
  mattr_accessor :navigational_formats
  @@navigational_formats = ["*/*", :html]

  # 设置为true时，注销用户会注销所有其他范围。
  mattr_accessor :sign_out_all_scopes
  @@sign_out_all_scopes = true

  # 注销时使用的默认方法。
  mattr_accessor :sign_out_via
  @@sign_out_via = :delete

  # 所有Devise控制器的默认父类。默认为ApplicationController，这应该
  # 尽早设置。
  mattr_accessor :parent_controller
  @@parent_controller = "ApplicationController"

  # 所有Devise邮件的默认父类。默认为ActionMailer::Base。这应该尽早
  # 设置。
  mattr_accessor :parent_mailer
  @@parent_mailer = "ActionMailer::Base"

  # Devise路由应该用来生成路由。默认 :main_app。应按顺序被引擎覆盖
  # 提供自定义路由。
  mattr_accessor :router_name
  @@router_name = nil

  # 设置omniauth路径前缀，以便在Devise中使用可装的引擎。
  mattr_accessor :omniauth_path_prefix
  @@omniauth_path_prefix = nil

  # 设置验证时是否应清除CSRF令牌。
  mattr_accessor :clean_up_csrf_token_on_authentication
  @@clean_up_csrf_token_on_authentication = true

  # 如果为false，Devise将不会尝试在急切加载时重新加载路由。这可以减少启动程序所需的时间，
  # 但是如果您的应用程序需要在应用程序启动时加载Devise映射，将无法启动。
  mattr_accessor :reload_routes
  @@reload_routes = true

  # 私有配置

  # 存储范围映射
  mattr_reader :mappings
  @@mappings = {}

  # OmniAuth配置信息
  mattr_reader :omniauth_configs
  @@omniauth_configs = {}

  # 定义添加映射时调用的一组模块。
  mattr_reader :helpers
  @@helpers = Set.new
  @@helpers << Devise::Controllers::Helpers

  # 与warden交互的私有方法
  mattr_accessor :warden_config
  @@warden_config = nil
  @@warden_config_blocks = []

  # 如果为true，请输入偏执模式以避免用户枚举。
  mattr_accessor :paranoid
  @@paranoid = false

  # 如果为true，则警告用户它们是否只使用了倒数第二次的身份验证尝试。
  mattr_accessor :last_attempt_warning
  @@last_attempt_warning = true

  # 存储令牌生成器
  mattr_accessor :token_generator
  @@token_generator = nil

  # 设置为false时，更改密码不会自动登陆用户。
  mattr_accessor :sign_in_after_change_password
  @@sign_in_after_change_password = true

  def self.rails51? # :nodoc:
    Rails.gem_version >= Gem::Version.new("5.1.x")
  end

  def self.activerecord51? # :nodoc:
    defined?(ActiveRecord) && ActiveRecord.gem_version >= Gem::Version.new("5.1.x")
  end

  # Default way to set up Devise. Run rails generate devise_install to create
  # a fresh initializer with all configuration values.
  def self.setup
    yield self
  end

  class Getter
    def initialize(name)
      @name = name
    end

    def get
      ActiveSupport::Dependencies.constantize(@name)
    end
  end

  def self.ref(arg)
    ActiveSupport::Dependencies.reference(arg)
    Getter.new(arg)
  end

  def self.available_router_name
    router_name || :main_app
  end

  def self.omniauth_providers
    omniauth_configs.keys
  end

  # Get the mailer class from the mailer reference object.
  def self.mailer
    @@mailer_ref.get
  end

  # Set the mailer reference object to access the mailer.
  def self.mailer=(class_name)
    @@mailer_ref = ref(class_name)
  end
  self.mailer = "Devise::Mailer"

  # 向Devise添加映射的小方法。
  def self.add_mapping(resource, options)
    mapping = Devise::Mapping.new(resource, options)
    @@mappings[mapping.name] = mapping
    @@default_scope ||= mapping.name
    @@helpers.each { |h| h.define_helpers(mapping) }
    mapping
  end

  # 注册可用的devise模块。对于devise提供的标准模块，这个方法从lib/devise/modules.rb中调用。需要使用此方法显式
  # 添加第三方模块。 
  #
  # 注意，使用此方法添加模块不会导致在身份验证的过程中使用它。需要在模型类定义中使用devise方法来使用模块。
  #
  # == Options:
  #
  #   +model+      - String representing the load path to a custom *model* for this module (to autoload.)
  #   +controller+ - Symbol representing the name of an existing or custom *controller* for this module.
  #   +route+      - Symbol representing the named *route* helper for this module.
  #   +strategy+   - Symbol representing if this module got a custom *strategy*.
  #   +insert_at+  - Integer representing the order in which this module's model will be included
  #
  # All values, except :model, accept also a boolean and will have the same name as the given module
  # name.
  #
  # == Examples:
  #
  #   Devise.add_module(:party_module)
  #   Devise.add_module(:party_module, strategy: true, controller: :sessions)
  #   Devise.add_module(:party_module, model: 'party_module/model')
  #   Devise.add_module(:party_module, insert_at: 0)
  #
  def self.add_module(module_name, options = {})
    options.assert_valid_keys(:strategy, :model, :controller, :route, :no_input, :insert_at)

    ALL.insert (options[:insert_at] || -1), module_name

    if strategy = options[:strategy]
      strategy = (strategy == true ? module_name : strategy)
      STRATEGIES[module_name] = strategy
    end

    if controller = options[:controller]
      controller = (controller == true ? module_name : controller)
      CONTROLLERS[module_name] = controller
    end

    if options[:no_input]
      NO_INPUT << strategy
    end

    route = options[:route]
    if route
      if route.is_a?(TrueClass)
        key, value = module_name, []
      elsif route.is_a?(Symbol)
        key, value = route, []
      elsif route.is_a?(Hash)
        key, value = route.keys.first, route.values.flatten
      else
        raise ArgumentError, ":route should be true, a Symbol or a Hash"
      end

      URL_HELPERS[key] ||= []
      URL_HELPERS[key].concat(value)
      URL_HELPERS[key].uniq!

      ROUTES[module_name] = key
    end # if route .. end

    if options[:model]
      path = (options[:model] == true ? "devise/models/#{module_name}" : options[:model])
      camelized = ActiveSupport::Inflector.camelize(module_name.to_s)
      Devise::Models.send(:autoload, camelized.to_sym, path)
    end

    Devise::Mapping.add_module module_name
  end

  # Sets warden configuration using a block that will be invoked on warden
  # initialization.
  #
  #  Devise.setup do |config|
  #    config.allow_unconfirmed_access_for = 2.days
  #
  #    config.warden do |manager|
  #      # Configure warden to use other strategies, like oauth.
  #      manager.oauth(:twitter)
  #    end
  #  end
  def self.warden(&block)
    @@warden_config_blocks << block
  end

  # Specify an OmniAuth provider.
  #
  #   config.omniauth :github, APP_ID, APP_SECRET
  #
  def self.omniauth(provider, *args)
    config = Devise::OmniAuth::Config.new(provider, args)
    @@omniauth_configs[config.strategy_name.to_sym] = config
  end

  # 为ActiveController和ActiveView include helpers
  def self.include_helpers(scope)
    ActiveSupport.on_load(:action_controller) do
      if defined?(scope::Helpers)
        include scope::Helpers
      end
      include scope::UrlHelpers
    end

    ActiveSupport.on_load(:action_view) do
      include scope::UrlHelpers
    end
  end

  # Regenerates url helpers considering Devise.mapping
  def self.regenerate_helpers!
    Devise::Controllers::UrlHelpers.remove_helpers!
    Devise::Controllers::UrlHelpers.generate_helpers!
  end

  # A method used internally to complete the setup of warden manager after routes are loaded.
  # See lib/devise/rails/routes.rb - ActionDispatch::Routing::RouteSet#finalize_with_devise!
  def self.configure_warden! #:nodoc:
    @@warden_configured ||= begin
      warden_config.failure_app   = Devise::Delegator.new
      warden_config.default_scope = Devise.default_scope
      warden_config.intercept_401 = false

      Devise.mappings.each_value do |mapping|
        warden_config.scope_defaults mapping.name, strategies: mapping.strategies

        warden_config.serialize_into_session(mapping.name) do |record|
          mapping.to.serialize_into_session(record)
        end

        warden_config.serialize_from_session(mapping.name) do |args|
          mapping.to.serialize_from_session(*args)
        end
      end

      @@warden_config_blocks.map { |block| block.call Devise.warden_config }
      true
    end
  end

  # Generate a friendly string randomly to be used as token.
  # By default, length is 20 characters.
  def self.friendly_token(length = 20)
    # To calculate real characters, we must perform this operation.
    # See SecureRandom.urlsafe_base64
    rlength = (length * 3) / 4
    SecureRandom.urlsafe_base64(rlength).tr('lIO0', 'sxyz')
  end

  # constant-time comparison algorithm to prevent timing attacks
  def self.secure_compare(a, b)
    return false if a.blank? || b.blank? || a.bytesize != b.bytesize
    l = a.unpack "C#{a.bytesize}"

    res = 0
    b.each_byte { |byte| res |= byte ^ l.shift }
    res == 0
  end
end

require 'warden'
require 'devise/mapping'
require 'devise/models'
require 'devise/modules'
require 'devise/rails'
