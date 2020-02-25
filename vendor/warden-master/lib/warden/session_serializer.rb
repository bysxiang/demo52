# encoding: utf-8
# frozen_string_literal: true
module Warden
  class SessionSerializer
    attr_reader :env

    def initialize(env)
      @env = env
    end

    def key_for(scope)
      "warden.user.#{scope}.key"
    end

    def serialize(user)
      user
    end

    def deserialize(key)
      key
    end

    def store(user, scope)
      puts "进入store===========, user: #{user}, current_xx: #{user.current_xx}, scope: #{scope}"
      if ! user
        return
      end

      method_name = "#{scope}_serialize"
      specialized = respond_to?(method_name)

      puts "输出method_name: #{method_name}, specialized: #{specialized}"

      puts "输出self: #{self.class}"
      p self.nesting
      


      session[key_for(scope)] = specialized ? send(method_name, user) : serialize(user)
    end

    def fetch(scope)
      key = session[key_for(scope)]
      return nil unless key

      method_name = "#{scope}_deserialize"
      user = respond_to?(method_name) ? send(method_name, key) : deserialize(key)
      delete(scope) unless user
      user
    end

    def stored?(scope)
      !!session[key_for(scope)]
    end

    def delete(scope, user=nil)
      session.delete(key_for(scope))
    end

    # We can't cache this result because the session can be lazy loaded
    def session
      env["rack.session"] || {}
    end
  end # SessionSerializer
end # Warden