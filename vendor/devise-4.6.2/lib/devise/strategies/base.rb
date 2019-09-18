# frozen_string_literal: true

module Devise
  module Strategies
    # Devise基本策略类。负责验证正确的scope和mapping。
    class Base < ::Warden::Strategies::Base
      # 如果无法验证CSRF，我们将关闭任何类型的存储。
      def store?
        !env["devise.skip_storage"]
      end

      # 检查是否为devise提供了有效的scope，并根据该scope查找mapping。
      def mapping
        @mapping ||= begin
          mapping = Devise.mappings[scope]
          if ! mapping
            raise "Could not find mapping for #{scope}"
          else
            mapping
          end
          
        end
      end

    end

  end
end
