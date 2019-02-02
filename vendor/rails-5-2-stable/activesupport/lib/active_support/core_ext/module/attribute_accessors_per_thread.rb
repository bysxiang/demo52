# frozen_string_literal: true

require "active_support/core_ext/array/extract_options"
require "active_support/core_ext/regexp"

# 扩展了Module对象，使得类/模块可以通过实例访问器访问类/模块的属性，就行访问本地attr*
# 属性一样，但这是在每个线程的基础上。
#
# 因此值的范围在模块的类名下的Thread.current空间内。
class Module
  # 定义每个线程的类属性，并创建类与实例读取器方法
  # 
  # 如果之前没有定义，则将每个线程类的底层类变量设置为Nil.
  #
  #   module Current
  #     thread_mattr_reader :user
  #   end
  #
  #   Current.user # => nil
  #   Thread.current[:attr_Current_user] = "DHH"
  #   Current.user # => "DHH"
  #
  # 属性名称必须是一个有效的Ruby方法名(符合Ruby方法命名规范)。
  #
  #   module Foo
  #     thread_mattr_reader :"1_Badname"
  #   end
  #   # => NameError: invalid attribute name: 1_Badname
  #
  # 如果你不想创建实例读取器方法，请通过instance_reader: false
  # 或instance_accessor: false
  #
  #   class Current
  #     thread_mattr_reader :user, instance_reader: false
  #   end
  #
  #   Current.new.user # => NoMethodError
  def thread_mattr_reader(*syms) # :nodoc:
    options = syms.extract_options!

    syms.each do |sym|
      if ! /^[_A-Za-z]\w*$/.match?(sym)
        raise NameError.new("invalid attribute name: #{sym}")
      end

      # The following generated method concatenates `name` because we want it
      # to work with inheritance via polymorphism.
      class_eval(<<-EOS, __FILE__, __LINE__ + 1)
        def self.#{sym}
          Thread.current["attr_" + name + "_#{sym}"]
        end
      EOS

      if ! options[:instance_reader] && ! options[:instance_accessor]
        class_eval(<<-EOS, __FILE__, __LINE__ + 1)
          def #{sym}
            self.class.#{sym}
          end
        EOS
      end
    end
  end
  alias :thread_cattr_reader :thread_mattr_reader

  # Defines a per-thread class attribute and creates a class and instance writer methods to
  # allow assignment to the attribute.
  #
  #   module Current
  #     thread_mattr_writer :user
  #   end
  #
  #   Current.user = "DHH"
  #   Thread.current[:attr_Current_user] # => "DHH"
  #
  # If you want to opt out of the creation of the instance writer method, pass
  # <tt>instance_writer: false</tt> or <tt>instance_accessor: false</tt>.
  #
  #   class Current
  #     thread_mattr_writer :user, instance_writer: false
  #   end
  #
  #   Current.new.user = "DHH" # => NoMethodError
  def thread_mattr_writer(*syms) # :nodoc:
    options = syms.extract_options!
    syms.each do |sym|
      raise NameError.new("invalid attribute name: #{sym}") unless /^[_A-Za-z]\w*$/.match?(sym)

      # The following generated method concatenates `name` because we want it
      # to work with inheritance via polymorphism.
      class_eval(<<-EOS, __FILE__, __LINE__ + 1)
        def self.#{sym}=(obj)
          Thread.current["attr_" + name + "_#{sym}"] = obj
        end
      EOS

      unless options[:instance_writer] == false || options[:instance_accessor] == false
        class_eval(<<-EOS, __FILE__, __LINE__ + 1)
          def #{sym}=(obj)
            self.class.#{sym} = obj
          end
        EOS
      end
    end
  end
  alias :thread_cattr_writer :thread_mattr_writer

  # Defines both class and instance accessors for class attributes.
  #
  #   class Account
  #     thread_mattr_accessor :user
  #   end
  #
  #   Account.user = "DHH"
  #   Account.user     # => "DHH"
  #   Account.new.user # => "DHH"
  #
  # If a subclass changes the value, the parent class' value is not changed.
  # Similarly, if the parent class changes the value, the value of subclasses
  # is not changed.
  #
  #   class Customer < Account
  #   end
  #
  #   Customer.user = "Rafael"
  #   Customer.user # => "Rafael"
  #   Account.user  # => "DHH"
  #
  # To opt out of the instance writer method, pass <tt>instance_writer: false</tt>.
  # To opt out of the instance reader method, pass <tt>instance_reader: false</tt>.
  #
  #   class Current
  #     thread_mattr_accessor :user, instance_writer: false, instance_reader: false
  #   end
  #
  #   Current.new.user = "DHH"  # => NoMethodError
  #   Current.new.user          # => NoMethodError
  #
  # Or pass <tt>instance_accessor: false</tt>, to opt out both instance methods.
  #
  #   class Current
  #     mattr_accessor :user, instance_accessor: false
  #   end
  #
  #   Current.new.user = "DHH"  # => NoMethodError
  #   Current.new.user          # => NoMethodError
  def thread_mattr_accessor(*syms)
    thread_mattr_reader(*syms)
    thread_mattr_writer(*syms)
  end
  alias :thread_cattr_accessor :thread_mattr_accessor
end
