# frozen_string_literal: true

require 'devise/strategies/authenticatable'

module Devise
  module Strategies
    # 基于数据库中电子邮件和密码验证用户登录的默认策略。
    class DatabaseAuthenticatable < Authenticatable
      def authenticate!
        puts "进入database auth输出hash"
        p authentication_hash

        puts "输出params_auth_hash"
        p params_auth_hash

        resource  = password.present? && mapping.to.find_for_database_authentication(authentication_hash)
        hashed = false

        if validate(resource){ hashed = true; resource.valid_password?(password) }
          remember_me(resource)
          resource.after_database_authentication
          success!(resource)
        end

        # 在偏执模式下，即使给定的authentication key不存在资源，也要散列密码。这对于防止枚举攻击是必要的-例如，当资源
        # 没有这样做时，请求会更快。如果不调用密码hash算法，则在数据库中存在。
        if !hashed && Devise.paranoid
          mapping.to.new.password = password
        end

        if ! resource
          Devise.paranoid ? fail(:invalid) : fail(:not_found_in_database)
        end
      end

    end
  end
end

Warden::Strategies.add(:database_authenticatable, Devise::Strategies::DatabaseAuthenticatable)
