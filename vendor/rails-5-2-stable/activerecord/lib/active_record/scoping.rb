# frozen_string_literal: true

require "active_support/per_thread_registry"

module ActiveRecord
  module Scoping
    extend ActiveSupport::Concern

    included do
      include Default
      include Named
    end

    module ClassMethods # :nodoc:
      def current_scope(skip_inherited_scope = false)
        ScopeRegistry.value_for(:current_scope, self, skip_inherited_scope)
      end

      def current_scope=(scope)
        ScopeRegistry.set_value_for(:current_scope, self, scope)
      end

      # Collects attributes from scopes that should be applied when creating
      # an AR instance for the particular class this is called on.
      def scope_attributes
        all.scope_for_create
      end

      # Are there attributes associated with this scope?
      def scope_attributes?
        current_scope
      end
    end

    def populate_with_current_scope_attributes # :nodoc:
      return unless self.class.scope_attributes?

      attributes = self.class.scope_attributes
      _assign_attributes(attributes) if attributes.any?
    end

    def initialize_internals_callback # :nodoc:
      super
      populate_with_current_scope_attributes
    end

    # 这个类为不同的类存储:current_scope和ignore_default_scope。它存储在线程local中，
    # 即可以通过ScopeRegistry.current来访问。
    #
    # 这个类允许你获取不同的scope值。例如，如果你正在尝试获取+Board+模型的current_scope,
    # 可以使用下面的代码：
    #
    #   registry = ActiveRecord::Scoping::ScopeRegistry
    #   registry.set_value_for(:current_scope, Board, some_new_scope)
    #
    # 现在你可以运行:
    #
    #   registry.value_for(:current_scope, Board)
    #
    # 你将获得+some_new_scope+中定义的任何内容。#value_for和#set_value_for方法被委托给了当前
    # 的ScopeRegistry对象，所以刚才的例子也可以这样调用：
    #
    #   ActiveRecord::Scoping::ScopeRegistry.set_value_for(:current_scope,
    #       Board, some_new_scope)
    class ScopeRegistry # :nodoc:
      # 通过这个模块重写了method_missing，定义了delegate 到当前线程实例，从而
      # 可以通过调用ActiveRecord::Scoping::ScopeRegistry.value_for等方法
      extend ActiveSupport::PerThreadRegistry 

      VALID_SCOPE_TYPES = [:current_scope, :ignore_default_scope]

      def initialize
        @registry = Hash.new { |hash, key| hash[key] = {} }
      end

      # Obtains the value for a given +scope_type+ and +model+.
      def value_for(scope_type, model, skip_inherited_scope = false)
        raise_invalid_scope_type!(scope_type)

        if skip_inherited_scope
          return @registry[scope_type][model.name]
        else
          klass = model
          base = model.base_class
          while klass <= base
            value = @registry[scope_type][klass.name]
            if value
              return value
            else
              klass = klass.superclass
            end
            
          end


        end

      end # def value_for .. end

      # Sets the +value+ for a given +scope_type+ and +model+.
      def set_value_for(scope_type, model, value)
        raise_invalid_scope_type!(scope_type)
        @registry[scope_type][model.name] = value
      end

      private

        def raise_invalid_scope_type!(scope_type)
          if !VALID_SCOPE_TYPES.include?(scope_type)
            raise ArgumentError, "Invalid scope type '#{scope_type}' sent to the registry. Scope types must be included in VALID_SCOPE_TYPES"
          end
        end
    end
  end
end
