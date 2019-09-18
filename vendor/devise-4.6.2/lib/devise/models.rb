# frozen_string_literal: true

module Devise
  module Models
    class MissingAttribute < StandardError
      def initialize(attributes)
        @attributes = attributes
      end

      def message
        "The following attribute(s) is (are) missing on your model: #{@attributes.join(", ")}"
      end
    end

    # 为Devise和给定模块创建配置值。
    # 为给定的类添加实例方法
    #
    #   Devise::Models.config(Devise::Models::DatabaseAuthenticatable, :stretches)
    #
    # 上面的行创建:
    #
    #   1) 一个被称为Devise.stretches的访问器。默认使用的值。
    #
    #   2) 你模型的一些类方法Model.stretches和Model.stretches=方法优先级高
    #      Devise.stretches。
    #
    #   3) 和一个实例方法stretches。
    #
    # 要添加类方法，你需要在给定的类中定义一个模块类方法。
    #
    # 为给定的模块，添加实例方法，如果存在实例方法或超类的实例方法，返回实例方法或继承的实例方法
    # ，如果不存在，调用Devise模块的相关类方法。
    def self.config(mod, *accessors) #:nodoc:
      class << mod; attr_accessor :available_configs; end
      mod.available_configs = accessors

      accessors.each do |accessor|
        mod.class_eval <<-METHOD, __FILE__, __LINE__ + 1
          def #{accessor}
            if defined?(@#{accessor})
              @#{accessor}
            elsif superclass.respond_to?(:#{accessor})
              superclass.#{accessor}
            else
              Devise.#{accessor}
            end
          end

          def #{accessor}=(value)
            @#{accessor} = value
          end
        METHOD
      end
    end

    def self.check_fields!(klass)
      failed_attributes = []
      instance = klass.new

      klass.devise_modules.each do |mod|
        constant = const_get(mod.to_s.classify)

        constant.required_fields(klass).each do |field|
          failed_attributes << field unless instance.respond_to?(field)
        end
      end

      if failed_attributes.any?
        fail Devise::Models::MissingAttribute.new(failed_attributes)
      end
    end

    # 在你的模型中包含devise模块:
    #
    #   devise :database_authenticatable, :confirmable, :recoverable
    #
    # You can also give any of the devise configuration values in form of a hash,
    # with specific values for this model. Please check your Devise initializer
    # for a complete description on those values.
    #
    def devise(*modules)
      options = modules.extract_options!.dup

      selected_modules = modules.map(&:to_sym).uniq.sort_by do |s|
        Devise::ALL.index(s) || -1  # follow Devise::ALL order
      end

      # 在模型类不执行
      devise_modules_hook! do
        include Devise::Models::Authenticatable

        selected_modules.each do |m|
          mod = Devise::Models.const_get(m.to_s.classify)

          if mod.const_defined?("ClassMethods")
            class_mod = mod.const_get("ClassMethods")
            extend class_mod

            if class_mod.respond_to?(:available_configs)
              available_configs = class_mod.available_configs
              available_configs.each do |config|
                if ! options.key?(config)
                  next
                else
                  send(:"#{config}=", options.delete(config))
                end
              end
            end
          end

          include mod
        end

        self.devise_modules |= selected_modules
        options.each { |key, value| send(:"#{key}=", value) }
      end
    end

    # The hook which is called inside devise.
    # So your ORM can include devise compatibility stuff.
    def devise_modules_hook!
      yield
    end
  end
end

require 'devise/models/authenticatable'
