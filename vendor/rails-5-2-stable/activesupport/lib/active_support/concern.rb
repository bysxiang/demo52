# frozen_string_literal: true

module ActiveSupport
  # 一个典型的模块是这样的:
  #
  #   module M
  #     def self.included(base)
  #       base.extend ClassMethods
  #       base.class_eval do
  #         scope :disabled, -> { where(disabled: true) }
  #       end
  #     end
  #
  #     module ClassMethods
  #       ...
  #     end
  #   end
  #
  # 通过使用<tt>ActiveSupport::Concern</tt>，可以将上述模块写为:
  #
  #   require 'active_support/concern'
  #
  #   module M
  #     extend ActiveSupport::Concern
  #
  #     included do
  #       scope :disabled, -> { where(disabled: true) }
  #     end
  #
  #     class_methods do
  #       ...
  #     end
  #   end
  #
  # 而且，它优雅地处理模块依赖性。给出一个+Foo+和+Bar+模块，后者依赖前者，我们通常会这么写:
  #
  #   module Foo
  #     def self.included(base)
  #       base.class_eval do
  #         def self.method_injected_by_foo
  #           ...
  #         end
  #       end
  #     end
  #   end
  #
  #   module Bar
  #     def self.included(base)
  #       base.method_injected_by_foo
  #     end
  #   end
  #
  #   class Host
  #     include Foo # 我们需要为Bar包含这种依赖
  #     include Bar # Bar是Host真正需要的模块
  #   end
  #
  # 但+Host+为什么要关心+Bar+的依赖关系，也就是+Foo+? 我们可以尝试隐藏这些+Host+
  # 直接include +Foo+，+Foo+去include +Bar+
  #
  #   module Bar
  #     include Foo
  #     def self.included(base)
  #       base.method_injected_by_foo
  #     end
  #   end
  #
  #   class Host
  #     include Bar
  #   end
  #
  # 不幸的是，这将不起作用，因为当+Foo+被包含进来时，它的base是+Bar+模块，而不是+Host+类。
  # <tt>ActiveSupport::Concern</tt>可以正确处理依赖:
  #
  #   require 'active_support/concern'
  #
  #   module Foo
  #     extend ActiveSupport::Concern
  #     included do
  #       def self.method_injected_by_foo
  #         ...
  #       end
  #     end
  #   end
  #
  #   module Bar
  #     extend ActiveSupport::Concern
  #     include Foo
  #
  #     included do
  #       self.method_injected_by_foo
  #     end
  #   end
  #
  #   class Host
  #     include Bar # 它可以工作，现在Bar处理它的依赖项。
  #   end
  # 简单来说，这个模块重写了append_features, included回调
  # included回调可被模块单独调用，它用于需要在include一个模块
  # 它可以处理
  module Concern
    class MultipleIncludedBlocks < StandardError #:nodoc:
      def initialize
        super "Cannot define multiple 'included' blocks for a Concern"
      end
    end

    # 当有模块继承此模块时，它包含此模块中的实例方法
    # 到base中，这个方法在base模块中定义了@_dependencies实例
    # 变量@_dependencies
    # 它保存着当前的模块依赖着那些模块
    def self.extended(base) #:nodoc:
      base.instance_variable_set(:@_dependencies, [])
    end

    def append_features(base)
      if base.instance_variable_defined?(:@_dependencies)
        base.instance_variable_get(:@_dependencies) << self
        false
      else
        if base < self
          return false
        else
          # 这里是一个递归操作，
          @_dependencies.each { |dep| base.include(dep) }
          super
          if const_defined?(:ClassMethods)
            base.extend const_get(:ClassMethods)
          end
          if instance_variable_defined?(:@_included_block)
            base.class_eval(&@_included_block)
          end
        end
        
      end # else .. end
    end # append_features .. end

    # 重载方法，base为nil时，需要提供一个块，它保存在
    # 模块中，待最终宿主include时，可以全部执行这些块，
    # 最终这些块定义在宿主类或模块中。如果不需要在最终宿主
    # 模块或类中执行相关代码，不必使用Concern
    def included(base = nil, &block)
      if base.nil?
        if instance_variable_defined?(:@_included_block)
          raise MultipleIncludedBlocks
        end

        @_included_block = block
      else
        super
      end
    end

    def class_methods(&class_methods_module_definition)
      mod = const_defined?(:ClassMethods, false) ?
        const_get(:ClassMethods) :
        const_set(:ClassMethods, Module.new)

      mod.module_eval(&class_methods_module_definition)
    end
  end
end
