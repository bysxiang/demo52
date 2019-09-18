# frozen_string_literal: true

require "active_support/dependencies"

module AbstractController
  module Helpers
    extend ActiveSupport::Concern

    included do
      class_attribute :_helpers, default: Module.new
      class_attribute :_helper_methods, default: Array.new
    end

    class MissingHelperError < LoadError
      def initialize(error, path)
        @error = error
        @path  = "helpers/#{path}.rb"
        set_backtrace error.backtrace

        if error.path =~ /^#{path}(\.rb)?$/
          super("Missing helper file helpers/%s.rb" % path)
        else
          raise error
        end
      end
    end

    module ClassMethods
      # When a class is inherited, wrap its helper module in a new module.
      # This ensures that the parent class's module can be changed
      # independently of the child class's.
      def inherited(klass)
        helpers = _helpers
        klass._helpers = Module.new { include helpers }
        klass.class_eval { default_helper_module! } unless klass.anonymous?
        super
      end

      # 将控制器方法声明为helper。例如，以下内容使current_user和logged_in?方法可以
      # 在视图中使用。
      #   class ApplicationController < ActionController::Base
      #     helper_method :current_user, :logged_in?
      #
      #     def current_user
      #       @current_user ||= User.find_by(id: session[:user])
      #     end
      #
      #     def logged_in?
      #       current_user != nil
      #     end
      #   end
      #
      # In a view:
      #  <% if logged_in? -%>Welcome, <%= current_user.name %><% end -%>
      #
      # ==== Parameters
      # * <tt>method[, method]</tt> - A name or names of a method on the controller
      #   to be made available on the view.
      def helper_method(*meths)
        meths.flatten!
        self._helper_methods += meths

        meths.each do |meth|
          _helpers.class_eval <<-ruby_eval, __FILE__, __LINE__ + 1
            def #{meth}(*args, &blk)                               # def current_user(*args, &blk)
              controller.send(%(#{meth}), *args, &blk)             #   controller.send(:current_user, *args, &blk)
            end                                                    # end
          ruby_eval
        end
      end

      # 找个helper类方法可以采用一系列辅助模块的名称，块或两者。
      #
      # ==== Options
      # * <tt>*args</tt> - 模块、符号或字符串
      # * <tt>block</tt> - 一个定义helper方法的块
      #
      # 当参数是模块时，它将直接包含在模块类中。
      #   helper FooHelper # => includes FooHelper
      #
      # 当参数是字符串或符号时，加载名称_helper文件名。第二个表单说明了如何包含 使用命名空间的自定义助手或者其他不包含helper定义
      # 的文件情况下，在一个标准加载路径中。
      #   helper :foo             # => requires 'foo_helper' and includes FooHelper
      #   helper 'resources/foo'  # => requires 'resources/foo_helper' and includes Resources::FooHelper
      #
      # 此外，此helper类方法还可以接受和执行一个块，从而使定义的方法可用在模板。
      #
      #   # One line
      #   helper { def hello() "Hello, world!" end }
      #
      #   # Multi-line
      #   helper do
      #     def foo(bar)
      #       "#{bar} is the very best"
      #     end
      #   end
      #
      # 最后，所有上述样式可以混合在一起，符号、字符串、模块和块。
      #
      #   helper(:three, BlindHelper) { def mice() 'mice' end }
      #
      def helper(*args, &block)
        modules_for_helpers(args).each do |mod|
          add_template_helper(mod)
        end

        _helpers.module_eval(&block) if block_given?
      end

      # Clears up all existing helpers in this class, only keeping the helper
      # with the same name as this class.
      def clear_helpers
        inherited_helper_methods = _helper_methods
        self._helpers = Module.new
        self._helper_methods = Array.new

        inherited_helper_methods.each { |meth| helper_method meth }
        default_helper_module! unless anonymous?
      end

      # Returns a list of modules, normalized from the acceptable kinds of
      # helpers with the following behavior:
      #
      # String or Symbol:: :FooBar or "FooBar" becomes "foo_bar_helper",
      # and "foo_bar_helper.rb" is loaded using require_dependency.
      #
      # Module:: No further processing
      #
      # After loading the appropriate files, the corresponding modules
      # are returned.
      #
      # ==== Parameters
      # * <tt>args</tt> - An array of helpers
      #
      # ==== Returns
      # * <tt>Array</tt> - A normalized list of modules for the list of
      #   helpers provided.
      def modules_for_helpers(args)
        args.flatten.map! do |arg|
          case arg
          when String, Symbol
            file_name = "#{arg.to_s.underscore}_helper"
            begin
              require_dependency(file_name)
            rescue LoadError => e
              raise AbstractController::Helpers::MissingHelperError.new(e, file_name)
            end

            mod_name = file_name.camelize
            begin
              mod_name.constantize
            rescue LoadError
              # dependencies.rb gives a similar error message but its wording is
              # not as clear because it mentions autoloading. To the user all it
              # matters is that a helper module couldn't be loaded, autoloading
              # is an internal mechanism that should not leak.
              raise NameError, "Couldn't find #{mod_name}, expected it to be defined in helpers/#{file_name}.rb"
            end
          when Module
            arg
          else
            raise ArgumentError, "helper must be a String, Symbol, or Module"
          end
        end
      end

      private
        # Makes all the (instance) methods in the helper module available to templates
        # rendered through this controller.
        #
        # ==== Parameters
        # * <tt>module</tt> - The module to include into the current helper module
        #   for the class
        def add_template_helper(mod)
          _helpers.module_eval { include mod }
        end

        def default_helper_module!
          module_name = name.sub(/Controller$/, "".freeze)
          module_path = module_name.underscore
          helper module_path
        rescue LoadError => e
          raise e unless e.is_missing? "helpers/#{module_path}_helper"
        rescue NameError => e
          raise e unless e.missing_name? "#{module_name}Helper"
        end
    end
  end
end
