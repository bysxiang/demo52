# frozen_string_literal: true

require "active_support/option_merger"

class Object
  # 一种优雅的方法，可以重复的选项值传递给一系列方法调用。块中调用的每个方法，块变量
  # 为接收器，将其选项与默认+options+合并提供。对块鼻哪里的每个方法都必须接受一个
  # hash 选项并作为最后一个参数。
  #
  # 没有<tt>with_options</tt>，此代码包含重复代码:
  #
  #   class Account < ActiveRecord::Base
  #     has_many :customers, dependent: :destroy
  #     has_many :products,  dependent: :destroy
  #     has_many :invoices,  dependent: :destroy
  #     has_many :expenses,  dependent: :destroy
  #   end
  #
  # 使用 <tt>with_options</tt>，我们可以移除重复选项
  #
  #   class Account < ActiveRecord::Base
  #     with_options dependent: :destroy do |assoc|
  #       assoc.has_many :customers
  #       assoc.has_many :products
  #       assoc.has_many :invoices
  #       assoc.has_many :expenses
  #     end
  #   end
  #
  # 它也可以与显式接收器一起使用:
  #
  #   I18n.with_options locale: user.locale, scope: 'newsletter' do |i18n|
  #     subject i18n.t :subject
  #     body    i18n.t :body, user_name: user.name
  #   end
  #
  # 当您不传递显式接收器时，它将在合并选项上下文中执行整个块:
  #
  #   class Account < ActiveRecord::Base
  #     with_options dependent: :destroy do
  #       has_many :customers
  #       has_many :products
  #       has_many :invoices
  #       has_many :expenses
  #     end
  #   end
  #
  # <tt>with_options</tt> 也可以嵌套，因为调用被转发到其接受者。
  #
  # 注意: 除了自己的嵌套级别外，每个嵌套级别还将合并继承的默认值。
  #
  #   class Post < ActiveRecord::Base
  #     with_options if: :persisted?, length: { minimum: 50 } do
  #       validates :content, if: -> { content.present? }
  #     end
  #   end
  #
  # 代码相当于:
  #
  #   validates :content, length: { minimum: 50 }, if: -> { content.present? }
  #
  # 因此，忽略+if+键的继承默认值。
  #
  # 注意: 您不能在with_options中隐式调用类方法。您可以使用类名来访问这些方法：
  #
  #   class Phone < ActiveRecord::Base
  #     enum phone_number_type: [home: 0, office: 1, mobile: 2]
  #
  #     with_options presence: true do
  #       validates :phone_number_type, inclusion: { in: Phone.phone_number_types.keys }
  #     end
  #   end
  #
  def with_options(options, &block)
    option_merger = ActiveSupport::OptionMerger.new(self, options)
    block.arity.zero? ? option_merger.instance_eval(&block) : block.call(option_merger)
  end
end
