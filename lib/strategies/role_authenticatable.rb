# frozen_string_literal: true

require 'devise/strategies/authenticatable'

module Strategies

  class RoleAuthenticatable < Authenticatable
    
    def authenticate!
      user = Devise.warden.user(mapping.name)

      puts "输出user"
      p user

      u = Employee.first
      success!(u)
    end

  end
end

Warden::Strategies.add(:role_authenticatable, ::Strategies::RoleAuthenticatable)