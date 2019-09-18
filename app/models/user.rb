class User < ApplicationRecord
  with_options dependent: :destroy do |a|
    a.has_many :address
  end

  
end
