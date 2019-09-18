# frozen_string_literal: true

module Devise
  # ParameterSantizer处理应用程序中每个Devise范围的特定参数值。
  #
  # santizer知道devise默认参数(例如RegistrationsController的password和password_confirm)
  # ，并且可以扩展或更改控制器上的允许参数列表。
  #
  # === 允许新的参数(Permitting new parameters)
  #
  # 你可以使用before_action方法中的permit方法向允许列表添加新参数。
  # 
  #
  #    class ApplicationController < ActionController::Base
  #      before_action :configure_permitted_parameters, if: :devise_controller?
   #
  #      protected
  #
  #      def configure_permitted_parameters
  #        # 允许subscribe_newsletter参数和其他参数一起作为注册参数
  #        devise_parameter_sanitizer.permit(:sign_up, keys: [:subscribe_newsletter])
  #      end
  #    end
  #
  # 使用块会生成ActionController::Parameters对象，因此可以你能嵌套参数，并可以更好
  # 的控制控制器中参数的允许方式
  # 
  #
  #    def configure_permitted_parameters
  #      devise_parameter_sanitizer.permit(:sign_up) do |user|
  #        user.permit(newsletter_preferences: [])
  #      end
  #    end
  class ParameterSanitizer
    DEFAULT_PERMITTED_ATTRIBUTES = {
      sign_in: [:password, :remember_me],
      sign_up: [:password, :password_confirmation],
      account_update: [:password, :password_confirmation, :current_password]
    }

    def initialize(resource_class, resource_name, params)
      @auth_keys      = extract_auth_keys(resource_class)
      @params         = params
      @resource_name  = resource_name
      @permitted      = {}

      DEFAULT_PERMITTED_ATTRIBUTES.each_pair do |action, keys|
        permit(action, keys: keys)
      end
    end

    # Sanitize the parameters for a specific +action+.
    #
    # === Arguments
    #
    # * +action+ - A +Symbol+ with the action that the controller is
    #   performing, like +sign_up+, +sign_in+, etc.
    #
    # === Examples
    #
    #    # Inside the `RegistrationsController#create` action.
    #    resource = build_resource(devise_parameter_sanitizer.sanitize(:sign_up))
    #    resource.save
    #
    # Returns an +ActiveSupport::HashWithIndifferentAccess+ with the permitted
    # attributes.
    def sanitize(action)
      permissions = @permitted[action]

      if permissions.respond_to?(:call)
        cast_to_hash permissions.call(default_params)
      elsif permissions.present?
        cast_to_hash permit_keys(default_params, permissions)
      else
        unknown_action!(action)
      end
    end

    # 在action允许列表中添加或删除新参数。
    #
    # === Arguments
    #
    # * +action+ - 一个要Perfom的控制器action，它是一个符号，如sign_up, 
    #   sign_in等。
    # * +keys:+     - 一个数组，表示要permitted的keys
    # * +except:+   - 一个数据，表示要被排除的keys
    # * +block+     - 应用于允许操作的块的参数而不是基于Array的方法。块将使用
    #   ActionController::Parameters实例调用。
    #
    # === Examples
    #
    #   # 在sign_up action中允许新的参数
    #   devise_parameter_sanitizer.permit(:sign_up, keys: [:subscribe_newsletter])
    #
    #   # 在account_update action中异常password参数
    #   devise_parameter_sanitizer.permit(:account_update, except: [:password])
    #
    #   # 使用块形式完全覆盖我们permit的用于sign_up的参数
    #   devise_parameter_sanitizer.permit(:sign_up) do |user|
    #     user.permit(:email, :password, :password_confirmation)
    #   end
    #
    #
    # Returns nothing.
    def permit(action, keys: nil, except: nil, &block)
      if block_given?
        @permitted[action] = block
      end

      if keys.present?
        @permitted[action] ||= @auth_keys.dup
        @permitted[action].concat(keys)
      end

      if except.present?
        @permitted[action] ||= @auth_keys.dup
        @permitted[action] = @permitted[action] - except
      end
    end

    private

    # Cast a sanitized +ActionController::Parameters+ to a +HashWithIndifferentAccess+
    # that can be used elsewhere.
    #
    # Returns an +ActiveSupport::HashWithIndifferentAccess+.
    def cast_to_hash(params)
      # TODO: Remove the `with_indifferent_access` method call when we only support Rails 5+.
      params && params.to_h.with_indifferent_access
    end

    def default_params
      if hashable_resource_params?
        @params.fetch(@resource_name)
      else
        empty_params
      end
    end

    def hashable_resource_params?
      @params[@resource_name].respond_to?(:permit)
    end

    def empty_params
      ActionController::Parameters.new({})
    end

    def permit_keys(parameters, keys)
      parameters.permit(*keys)
    end

    def extract_auth_keys(klass)
      auth_keys = klass.authentication_keys

      auth_keys.respond_to?(:keys) ? auth_keys.keys : auth_keys
    end

    def unknown_action!(action)
      raise NotImplementedError, <<-MESSAGE.strip_heredoc
        "Devise doesn't know how to sanitize parameters for '#{action}'".
        If you want to define a new set of parameters to be sanitized use the
        `permit` method first:

          devise_parameter_sanitizer.permit(:#{action}, keys: [:param1, :param2, :param3])
      MESSAGE
    end
  end
end
