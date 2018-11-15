# frozen_string_literal: true

require "active_record/scoping/default"
require "active_record/scoping/named"

module ActiveRecord
  #
  # 这个类用于追踪已运行的迁移，它创建一个表。当迁移运行，将版本信息插入。
  # 这个类是一个模型类
  class SchemaMigration < ActiveRecord::Base # :nodoc:
    class << self
      def primary_key
        "version"
      end

      def table_name
        "#{table_name_prefix}#{ActiveRecord::Base.schema_migrations_table_name}#{table_name_suffix}"
      end

      def table_exists?
        connection.table_exists?(table_name)
      end

      def create_table
        unless table_exists?
          version_options = connection.internal_string_options_for_primary_key

          connection.create_table(table_name, id: false) do |t|
            t.string :version, version_options
          end
        end
      end

      def drop_table
        connection.drop_table table_name, if_exists: true
      end

      def normalize_migration_number(number)
        "%.3d" % number.to_i
      end

      def normalized_versions
        all_versions.map { |v| normalize_migration_number v }
      end

      def all_versions
        order(:version).pluck(:version)
      end
    end

    def version
      super.to_i
    end
  end
end
