# frozen_string_literal: true

module Devise
  module Controllers
    # 提供登录和注销功能。
    # 默认情况下包含在所有控制器中。
    module SignInOut
      # 如果会话中给定的范围已登陆，则返回true。如果没有给定作用域，则有任何登陆的都会返回true。
      # 这将运行身份验证钩子，可能导致从此方法抛出异常。如果你只想检查一下，如果此范围之前已经过验证
      # 而没有运行认证钩子，你可以直接调用warden.authenticated?(scope: scope)。
      def signed_in?(scope=nil)
        [scope || Devise.mappings.keys].flatten.any? do |_scope|
          warden.authenticate?(scope: _scope)
        end
      end

      # 登陆已经过身份验证的用户。注册后，此助手可用于记录用户。给sign_in的所有选项都传递给warden
      # 的set_user方法。
      # 如果你使用自定义warden策略和timeoutable模块，则必须在request中设置`env['devise.skip_timeout'] = true`以
      # 使用此方法，就行我们在会话控制器中一样:
      # https://github.com/plataformatec/devise/blob/master/app/controllers/devise/sessions_controller.rb#L7
      #
      # Examples:
      #
      #   sign_in :user, @user                      # sign_in(scope, resource)
      #   sign_in @user                             # sign_in(resource)
      #   sign_in @user, event: :authentication     # sign_in(resource, options)
      #   sign_in @user, store: false               # sign_in(resource, options)
      #
      def sign_in(resource_or_scope, *args)
        options  = args.extract_options!
        scope    = Devise::Mapping.find_scope!(resource_or_scope)
        resource = args.last || resource_or_scope

        expire_data_after_sign_in!

        if options[:bypass]
          ActiveSupport::Deprecation.warn(<<-DEPRECATION.strip_heredoc, caller)
          [Devise] bypass option is deprecated and it will be removed in future version of Devise.
          Please use bypass_sign_in method instead.
          Example:

            bypass_sign_in(user)
          DEPRECATION
          warden.session_serializer.store(resource, scope)
        elsif warden.user(scope) == resource && !options.delete(:force)
          # Do nothing. User already signed in and we are not forcing it.
          true
        else
          warden.set_user(resource, options.merge!(scope: scope))
        end
      end

      # 绕过warden回调登陆一个用户，并将该用户直接存储在会话中。此选项在warden已登录
      # 的情况下很有用，但我们希望在会话中刷新凭据。
      #
      # Examples:
      #
      #   bypass_sign_in @user, scope: :user
      #   bypass_sign_in @user
      def bypass_sign_in(resource, scope: nil)
        scope ||= Devise::Mapping.find_scope!(resource)
        expire_data_after_sign_in!

        # puts "输出warden.session_serializer"
        # p warden.session_serializer

        warden.session_serializer.store(resource, scope)
      end

      # 注销指定的用户或范围。此帮助程序对于在删除账户后注销用户非常有用。如果当前存在用户，并被
      # 注销，返回true，否则返回false。
      #
      # Examples:
      #
      #   sign_out :user     # sign_out(scope)
      #   sign_out @user     # sign_out(resource)
      #
      def sign_out(resource_or_scope=nil)
        if ! resource_or_scope
          return sign_out_all_scopes
        end

        scope = Devise::Mapping.find_scope!(resource_or_scope)
        user = warden.user(scope: scope, run_callbacks: false) # If there is no user

        warden.logout(scope)
        warden.clear_strategies_cache!(scope: scope)
        instance_variable_set(:"@current_#{scope}", nil)

        !!user
      end

      # Sign out all active users or scopes. This helper is useful for signing out all roles
      # in one click. This signs out ALL scopes in warden. Returns true if there was at least one logout
      # and false if there was no user logged in on all scopes.
      def sign_out_all_scopes(lock=true)
        users = Devise.mappings.keys.map { |s| warden.user(scope: s, run_callbacks: false) }

        warden.logout
        expire_data_after_sign_out!
        warden.clear_strategies_cache!
        warden.lock! if lock

        users.any?
      end

      private

      def expire_data_after_sign_in!
        # 如果会话尚未加载，session.keys将返回空数组。
        # 这在Rack和Rails中是一个bug。调用session.empty?强制加载会话
        session.empty?
        session.keys.grep(/^devise\./).each { |k| session.delete(k) }
      end

      alias :expire_data_after_sign_out! :expire_data_after_sign_in!
    end
  end
end
