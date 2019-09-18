# frozen_string_literal: true

require 'active_model/version'
require 'devise/hooks/activatable'
require 'devise/hooks/csrf_cleaner'

module Devise
  module Models
    # Authenticatable模块。保存用于身份验证的公共设置。
    #
    # == Options
    #
    # Authenticatable 添加以下这些选项:
    #
    #   * +authentication_keys+: 用于身份验证的参数. 默认是 [:email].
    #
    #   * +http_authentication_key+: 将通过HTTP AUTH传递的用户名映射到此参数。默认为+authentication_keys+
    #     的第一个参数
    #
    #   * +request_keys+: 来自用于身份验证的请求对象的参数。通过指定符号(应该是请求方法)，它自动传递给
    #     find_for_authentication方法并查找模型。
    #
    #     例如，如果您将:request_keys设置为[:subdomain]，:subdomain将被考虑作为认证的主键。也可以是一个hash
    #     , 其中值是布尔值指定的是否需要该值。
    #
    #   * +http_authenticatable+: 如果此模型允许http身份验证。默认为false。它也可以接受一个数组，该数组指定
    #     允许http的策略。
    #
    #   * +params_authenticatable+: 如果此模型允许通过请求参数进行身份验证。默认为true。它也可以接受一个数组，
    #     指定应允许的params身份验证策略。
    #
    #   * +skip_session_storage+: 默认情况下，Devise会将用户存储在会话中。默认情况下设置
    #     skip_session_storage: [:http_auth].
    #
    # == active_for_authentication?
    #
    # 在对用户进行身份验证之后，在每个请求中，Devise通过model.active_for_authentication?检查您的模型是否处于活动状态。
    # 其他devise模块会覆盖此方法。例如，:confirmable重写.active_for_authentication?,当您的模型已确认无误，它返回true。
    #
    # 您也可以重写此方法，但是不要忘记调用super:
    #
    #   def active_for_authentication?
    #     super && special_condition_is_valid?
    #   end
    #
    # 每当active_for_authentication?返回false，Devise使用inactive_message方法询问模型处于非活动状态的原因。你也可以
    # 覆盖它
    #
    #   def inactive_message
    #     special_condition_is_valid? ? super : :special_condition_is_not_valid
    #   end
    #
    module Authenticatable
      extend ActiveSupport::Concern

      BLACKLIST_FOR_SERIALIZATION = [:encrypted_password, :reset_password_token, :reset_password_sent_at,
        :remember_created_at, :sign_in_count, :current_sign_in_at, :last_sign_in_at, :current_sign_in_ip,
        :last_sign_in_ip, :password_salt, :confirmation_token, :confirmed_at, :confirmation_sent_at,
        :remember_token, :unconfirmed_email, :failed_attempts, :unlock_token, :locked_at]

      included do
        class_attribute :devise_modules, instance_writer: false
        self.devise_modules ||= []

        before_validation :downcase_keys
        before_validation :strip_whitespace
      end

      def self.required_fields(klass)
        []
      end

      # 检查当前对象是否对身份验证有效。这种方法和find_for_authentication用于Warden::Strategy
      # 检查模型是否应该登录。
      #
      # 但是，不应覆盖此方法，而应重写active_for_authentication?和inactive_message方法。
      def valid_for_authentication?
        block_given? ? yield : true
      end

      def unauthenticated_message
        :invalid
      end

      def active_for_authentication?
        true
      end

      def inactive_message
        :inactive
      end

      def authenticatable_salt
      end

      # Redefine serializable_hash in models for more secure defaults.
      # By default, it removes from the serializable model all attributes that
      # are *not* accessible. You can remove this default by using :force_except
      # and passing a new list of attributes you want to exempt. All attributes
      # given to :except will simply add names to exempt to Devise internal list.
      def serializable_hash(options = nil)
        options = options.try(:dup) || {}
        options[:except] = Array(options[:except])

        if options[:force_except]
          options[:except].concat Array(options[:force_except])
        else
          options[:except].concat BLACKLIST_FOR_SERIALIZATION
        end

        super(options)
      end

      # Redefine inspect using serializable_hash, to ensure we don't accidentally
      # leak passwords into exceptions.
      def inspect
        inspection = serializable_hash.collect do |k,v|
          "#{k}: #{respond_to?(:attribute_for_inspect) ? attribute_for_inspect(k) : v.inspect}"
        end
        "#<#{self.class} #{inspection.join(", ")}>"
      end

      protected

      def devise_mailer
        Devise.mailer
      end

      # This is an internal method called every time Devise needs
      # to send a notification/mail. This can be overridden if you
      # need to customize the e-mail delivery logic. For instance,
      # if you are using a queue to deliver e-mails (active job, delayed
      # job, sidekiq, resque, etc), you must add the delivery to the queue
      # just after the transaction was committed. To achieve this,
      # you can override send_devise_notification to store the
      # deliveries until the after_commit callback is triggered.
      #
      # The following example uses Active Job's `deliver_later` :
      #
      #     class User
      #       devise :database_authenticatable, :confirmable
      #
      #       after_commit :send_pending_devise_notifications
      #
      #       protected
      #
      #       def send_devise_notification(notification, *args)
      #         # If the record is new or changed then delay the
      #         # delivery until the after_commit callback otherwise
      #         # send now because after_commit will not be called.
      #         if new_record? || changed?
      #           pending_devise_notifications << [notification, args]
      #         else
      #           render_and_send_devise_message(notification, *args)
      #         end
      #       end
      #
      #       private
      #
      #       def send_pending_devise_notifications
      #         pending_devise_notifications.each do |notification, args|
      #           render_and_send_devise_message(notification, *args)
      #         end
      #
      #         # Empty the pending notifications array because the
      #         # after_commit hook can be called multiple times which
      #         # could cause multiple emails to be sent.
      #         pending_devise_notifications.clear
      #       end
      #
      #       def pending_devise_notifications
      #         @pending_devise_notifications ||= []
      #       end
      #
      #       def render_and_send_devise_message(notification, *args)
      #         message = devise_mailer.send(notification, self, *args)
      #
      #         # Deliver later with Active Job's `deliver_later`
      #         if message.respond_to?(:deliver_later)
      #           message.deliver_later
      #         # Remove once we move to Rails 4.2+ only, as `deliver` is deprecated.
      #         elsif message.respond_to?(:deliver_now)
      #           message.deliver_now
      #         else
      #           message.deliver
      #         end
      #       end
      #
      #     end
      #
      def send_devise_notification(notification, *args)
        message = devise_mailer.send(notification, self, *args)
        # Remove once we move to Rails 4.2+ only.
        if message.respond_to?(:deliver_now)
          message.deliver_now
        else
          message.deliver
        end
      end

      def downcase_keys
        self.class.case_insensitive_keys.each { |k| apply_to_attribute_or_variable(k, :downcase) }
      end

      def strip_whitespace
        self.class.strip_whitespace_keys.each { |k| apply_to_attribute_or_variable(k, :strip) }
      end

      def apply_to_attribute_or_variable(attr, method)
        if self[attr]
          self[attr] = self[attr].try(method)

        # Use respond_to? here to avoid a regression where globally
        # configured strip_whitespace_keys or case_insensitive_keys were
        # attempting to strip or downcase when a model didn't have the
        # globally configured key.
        elsif respond_to?(attr) && respond_to?("#{attr}=")
          new_value = send(attr).try(method)
          send("#{attr}=", new_value)
        end
      end

      module ClassMethods
        Devise::Models.config(self, :authentication_keys, :request_keys, :strip_whitespace_keys,
          :case_insensitive_keys, :http_authenticatable, :params_authenticatable, :skip_session_storage,
          :http_authentication_key)

        def serialize_into_session(record)
          puts "输出record"
          p record

          [record.to_key, record.authenticatable_salt]
        end

        def serialize_from_session(key, salt)
          record = to_adapter.get(key)
          record if record && record.authenticatable_salt == salt
        end

        def params_authenticatable?(strategy)
          params_authenticatable.is_a?(Array) ?
            params_authenticatable.include?(strategy) : params_authenticatable
        end

        def http_authenticatable?(strategy)
          http_authenticatable.is_a?(Array) ?
            http_authenticatable.include?(strategy) : http_authenticatable
        end

        # Find first record based on conditions given (ie by the sign in form).
        # This method is always called during an authentication process but
        # it may be wrapped as well. For instance, database authenticatable
        # provides a `find_for_database_authentication` that wraps a call to
        # this method. This allows you to customize both database authenticatable
        # or the whole authenticate stack by customize `find_for_authentication.`
        #
        # Overwrite to add customized conditions, create a join, or maybe use a
        # namedscope to filter records while authenticating.
        # Example:
        #
        #   def self.find_for_authentication(tainted_conditions)
        #     find_first_by_auth_conditions(tainted_conditions, active: true)
        #   end
        #
        # Finally, notice that Devise also queries for users in other scenarios
        # besides authentication, for example when retrieving a user to send
        # an e-mail for password reset. In such cases, find_for_authentication
        # is not called.
        def find_for_authentication(tainted_conditions)
          find_first_by_auth_conditions(tainted_conditions)
        end

        def find_first_by_auth_conditions(tainted_conditions, opts={})
          to_adapter.find_first(devise_parameter_filter.filter(tainted_conditions).merge(opts))
        end

        # Find or initialize a record setting an error if it can't be found.
        def find_or_initialize_with_error_by(attribute, value, error=:invalid) #:nodoc:
          find_or_initialize_with_errors([attribute], { attribute => value }, error)
        end

        # Find or initialize a record with group of attributes based on a list of required attributes.
        def find_or_initialize_with_errors(required_attributes, attributes, error=:invalid) #:nodoc:
          attributes.try(:permit!)
          attributes = attributes.to_h.with_indifferent_access
                                 .slice(*required_attributes)
                                 .delete_if { |key, value| value.blank? }

          if attributes.size == required_attributes.size
            record = find_first_by_auth_conditions(attributes) and return record
          end

          new(devise_parameter_filter.filter(attributes)).tap do |record|
            required_attributes.each do |key|
              record.errors.add(key, attributes[key].blank? ? :blank : error)
            end
          end
        end

        protected

        def devise_parameter_filter
          @devise_parameter_filter ||= Devise::ParameterFilter.new(case_insensitive_keys, strip_whitespace_keys)
        end
      end
    end
  end
end
