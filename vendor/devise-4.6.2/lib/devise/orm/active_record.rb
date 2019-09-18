# frozen_string_literal: true

require 'orm_adapter/adapters/active_record'

ActiveSupport.on_load(:active_record) do
  # 让ORM的类继承下面模块的类方法
  extend Devise::Models
end
