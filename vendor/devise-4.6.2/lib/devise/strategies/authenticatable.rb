# frozen_string_literal: true

require 'devise/strategies/base'

module Devise
  module Strategies
    # 应该将此策略用作身份验证策略的基础。它从params或http授权头中检索参数。有关示例，请参阅
    # database_authenticatable。
    class Authenticatable < Base
      attr_accessor :authentication_hash, :authentication_type, :password

      def store?
        super && !mapping.to.skip_session_storage.include?(authentication_type)
      end

      # 正确设置了用户、密码等用于验证的信息，即返回true。
      def valid?
        valid_for_params_auth? || valid_for_http_auth?
      end

      # Override and set to false for things like OmniAuth that technically
      # run through Authentication (user_set) very often, which would normally
      # reset CSRF data in the session
      def clean_up_csrf?
        true
      end

    private

      # 接收一个资源并通过调用valid_for_authentication?检查是否有效，验证时将触发的块是可选的，它
      # 作为参数给出。检查Devise::Models::Authenticatable.valid_for_authentication?获取更多信息
      #
      # 如果无法验证资源，它将失败，并显示给定的未经身份验证的消息。
      def validate(resource, &block)
        result = resource && resource.valid_for_authentication?(&block)

        if result
          true
        else
          if resource
            fail!(resource.unauthenticated_message)
          end
          false
        end
      end

      # Get values from params and set in the resource.
      def remember_me(resource)
        resource.remember_me = remember_me? if resource.respond_to?(:remember_me=)
      end

      # Should this resource be marked to be remembered?
      def remember_me?
        valid_params? && Devise::TRUE_VALUES.include?(params_auth_hash[:remember_me])
      end

      # Check if this is a valid strategy for http authentication by:
      #
      #   * Validating if the model allows http authentication;
      #   * If any of the authorization headers were sent;
      #   * If all authentication keys are present;
      #
      def valid_for_http_auth?
        http_authenticatable? && request.authorization && with_authentication_hash(:http_auth, http_auth_hash)
      end

      # 检查这是不是一个有效的params 授权策略: 
      #
      #   * Validating if the model allows params authentication;
      #   * If the request hits the sessions controller through POST;
      #   * If the params[scope] returns a hash with credentials;
      #   * If all authentication keys are present;
      #
      def valid_for_params_auth?
        puts "输出params_auth_hash， authtable"
        p params_auth_hash

        result = params_authenticatable? && valid_params_request? &&
          valid_params? && with_authentication_hash(:params_auth, params_auth_hash)

        puts "输出self.authentication_hash"
        p self.authentication_hash

        return result
      end

      # Check if the model accepts this strategy as http authenticatable.
      def http_authenticatable?
        mapping.to.http_authenticatable?(authenticatable_name)
      end

      # 检查模型是否接受此策略为params authenticatable。
      def params_authenticatable?
        mapping.to.params_authenticatable?(authenticatable_name)
      end

      # Extract the appropriate subhash for authentication from params.
      def params_auth_hash
        params[scope]
      end

      # Extract a hash with attributes:values from the http params.
      def http_auth_hash
        keys = [http_authentication_key, :password]
        Hash[*keys.zip(decode_credentials).flatten]
      end

      # 默认情况下，如果控制器设置了适当的env变量，则请求是有效的。
      def valid_params_request?
        !!env["devise.allow_params_authentication"]
      end

      # 如果请求有效，最后检查params_auth_hash是否返回一个hash。
      def valid_params?
        params_auth_hash.is_a?(Hash)
      end

      # Note: unlike `Model.valid_password?`, this method does not actually
      # ensure that the password in the params matches the password stored in
      # the database. It only checks if the password is *present*. Do not rely
      # on this method for validating that a given password is correct.
      def valid_password?
        password.present?
      end

      # Helper to decode credentials from HTTP.
      def decode_credentials
        return [] unless request.authorization && request.authorization =~ /^Basic (.*)/mi
        Base64.decode64($1).split(/:/, 2)
      end

      # 从params_auth_hash或http_auth_hash设置身份验证hash和密码。
      # auth_values 包含email, password等信息
      # self.authentication_hash存储authentication_keys对应的值
      def with_authentication_hash(auth_type, auth_values)
        self.authentication_hash, self.authentication_type = {}, auth_type
        self.password = auth_values[:password]

        puts "输出auth_type: #{auth_type}, auth_values: #{auth_values}"

        parse_authentication_key_values(auth_values, authentication_keys) &&
        parse_authentication_key_values(request_values, request_keys)
      end

      def authentication_keys
        @authentication_keys ||= mapping.to.authentication_keys
      end

      def http_authentication_key
        # result = 

        @http_authentication_key ||= mapping.to.http_authentication_key || case authentication_keys
          when Array then authentication_keys.first
          when Hash then authentication_keys.keys.first
        end
      end

      def request_keys
        @request_keys ||= mapping.to.request_keys
      end

      def request_values
        keys = request_keys.respond_to?(:keys) ? request_keys.keys : request_keys
        values = keys.map { |k| self.request.send(k) }
        Hash[keys.zip(values)]
      end

      # 从hash(即登陆等操作中传递的email, password等信息)
      # 中提取authentication_keys中的值
      def parse_authentication_key_values(hash, keys)
        keys.each do |key, enforce|
          value = hash[key].presence
          if value
            self.authentication_hash[key] = value
          else
            if enforce != false
              return false
            end
          end
        end
        true
      end

      # 持有此类的authenticatable名称。使得Devise::Strategies::DatabaseAuthenticatable变的简单，
      # 变为 :database
      def authenticatable_name
        @authenticatable_name ||=
          ActiveSupport::Inflector.underscore(self.class.name.split("::").last).
            sub("_authenticatable", "").to_sym
      end
    end
  end
end
