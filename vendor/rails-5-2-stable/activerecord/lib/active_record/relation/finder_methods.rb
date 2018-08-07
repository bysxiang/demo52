# frozen_string_literal: true

require "active_support/core_ext/string/filters"

module ActiveRecord
  module FinderMethods
    ONE_AS_ONE = "1 AS one"

    # 通过id查找 - 可以一个特定的id（1），一个ids列表(1, 5, 6)，或ids数组([5, 6, 10])。如果无法为请求的id找到一条或多条记录，
    # 则将抛出RecordNotFound异常。如果主键是一个整数，通过id轻质使用+to_i+查找它的参数。
    #
    #   Person.find(1)          # returns the object for ID = 1
    #   Person.find("1")        # returns the object for ID = 1
    #   Person.find("31-sarah") # returns the object for ID = 31
    #   Person.find(1, 2, 6)    # returns an array for objects with IDs in (1, 2, 6)
    #   Person.find([7, 17])    # returns an array for objects with IDs in (7, 17)
    #   Person.find([1])        # returns an array for the object with ID = 1
    #   Person.where("administrator = 1").order("created_on DESC").find(1)
    #
    # 注意：返回的记录与您提供的id的顺序相同。如果你想要按数据库排序结果，可以使用ActiveRecord::QueryMethods#where
    # 方法并额外提供一个ActiveRecord::QueryMethods#order选项。但是AcitveRecord::QueryMethods#where方法不会抛出
    # ActiveRecord::RecordNotFound异常。
    #
    # ==== 使用查找锁
    #
    # 使用查找锁的示例：假设有两个并发事务：每个读visit == 2的人，对它加1并保存，结果此时有另一个人也在访问，两次访问
    # 保存为3.通过锁定行，第二行事务必须等到第一个完成。我们得到预期的person.visits == 4.
    #
    #   Person.transaction do
    #     person = Person.lock(true).find(1)
    #     person.visits += 1
    #     person.save!
    #   end
    #
    # ==== #find的变种
    #
    #   Person.where(name: 'Spartacus', rating: 4)
    #   # 返回可链式操作的列表 (可以为空)
    #
    #   Person.find_by(name: 'Spartacus', rating: 4)
    #   # 返回第一个对象或nil
    #
    #   Person.find_or_initialize_by(name: 'Spartacus', rating: 4)
    #   # 返回第一个实例或构造一个新实例(需要你手动调用.save来持久化到数据库)
    #
    #   Person.find_or_create_by(name: 'Spartacus', rating: 4)
    #   # 返回第一个实例或创建新的实例
    #
    # ==== find的替代方案
    #
    #   Person.where(name: 'Spartacus', rating: 4).exists?(conditions = :none)
    #   # 返回一个布尔值，指示是否存在具有给定条件的任何记录。
    #
    #   Person.where(name: 'Spartacus', rating: 4).select("field1, field2, field3")
    #   # 返回一个可链式操作的列表，实例只包括特定列
    #
    #   Person.where(name: 'Spartacus', rating: 4).ids
    #   # 返回一个ids的数组
    #   # returns an Array of ids.
    #
    #   Person.where(name: 'Spartacus', rating: 4).pluck(:field1, :field2)
    #   # 返回一个只包括特定字段的数组
    def find(*args)
      if block_given?
        return super
      else
        find_with_ids(*args)
      end
    end

    # 根据指定的条件查找第一个就。它没有隐式的排序，你需要自己指定。例如：
    # Card.order("id desc").find_by(ancestry_id: 2048)
    # 
    # 如果记录没有找到，返回nil
    #
    #   Post.find_by name: 'Spartacus', rating: 4
    #   Post.find_by "published_at < ?", 2.weeks.ago
    def find_by(arg, *args)
      where(arg, *args).take
    rescue ::RangeError
      nil
    end

    # 类似find_by, 如果没有找到记录，将抛出ActiveRecord::RecordNotFound异常
    def find_by!(arg, *args)
      where(arg, *args).take!
    rescue ::RangeError
      raise RecordNotFound.new("Couldn't find #{@klass.name} with an out of range value",
                               @klass.name, @klass.primary_key)
    end

    # 返回一条记录（如果提供了一个参数，则给出N条记录），不会隐式排序，取决于数据库实现。
    # 如果提供了order，它将被尊重。
    # 
    #   Person.take # returns an object fetched by SELECT * FROM people LIMIT 1
    #   Person.take(5) # returns 5 objects fetched by SELECT * FROM people LIMIT 5
    #   Person.where(["name LIKE '%?'", name]).take
    def take(limit = nil)
      limit ? find_take_with_limit(limit) : find_take
    end

    # 类似take方法，当没有找到记录时抛出异常。
    # 注意，他没有任何参数。
    def take!
      take || raise_record_not_found_exception!
    end

    # 查找第一个记录(如果提供了参数返回N条记录)。
    # 如果没有排序，将按主键排序
    #
    #   Person.first # returns the first object fetched by SELECT * FROM people ORDER BY people.id LIMIT 1
    #   Person.where(["user_name = ?", user_name]).first
    #   Person.where(["user_name = :u", { u: user_name }]).first
    #   Person.order("created_on DESC").offset(5).first
    #   Person.first(3) # returns the first three objects fetched by SELECT * FROM people ORDER BY people.id LIMIT 3
    #
    def first(limit = nil)
      if limit
        find_nth_with_limit(0, limit)
      else
        find_nth 0
      end
    end

    # 类似first方法，但是如果没有找到，将会抛出ActiveRecord::RecordNotFound异常
    # 注意：此方法不接受任何参数。
    def first!
      first || raise_record_not_found_exception!
    end

    # 查找最后一条记录 (如果提供了参数，返回多条记录)
    # 如果没有提供order定义，将按主键排序
    #
    #   Person.last # returns the last object fetched by SELECT * FROM people order by id desc limit
    #   Person.where(["user_name = ?", user_name]).last
    #   Person.order("created_on DESC").offset(5).last
    #   Person.last(3) # returns the last three objects fetched by SELECT * FROM people order by id desc limit 3
    def last(limit = nil)
      if loaded? || has_limit_or_offset?
        return find_last(limit)
      else
        result = ordered_relation.limit(limit)
        result = result.reverse_order!

        limit ? result.reverse : result.first
      end

      
    end

    # 类似last方法，但此方法如果没有找到就，会抛出ActiveRecord::RecordNotFound。
    # 注意此方法不接受任何参数。
    def last!
      last || raise_record_not_found_exception!
    end

    # 查找第二条记录。如果没有定义order，将按主键排序。
    #
    #   Person.second # returns the second object fetched by SELECT * FROM people
    #   Person.offset(3).second # returns the second object from OFFSET 3 (which is OFFSET 4)
    #   Person.where(["user_name = :u", { u: user_name }]).second
    def second
      find_nth 1
    end

    # 类似second方法，只是当找不到记录时会抛出ActiveRecord::RecordNotFound异常
    def second!
      second || raise_record_not_found_exception!
    end

    # Find the third record.
    # If no order is defined it will order by primary key.
    #
    #   Person.third # returns the third object fetched by SELECT * FROM people
    #   Person.offset(3).third # returns the third object from OFFSET 3 (which is OFFSET 5)
    #   Person.where(["user_name = :u", { u: user_name }]).third
    def third
      find_nth 2
    end

    # Same as #third but raises ActiveRecord::RecordNotFound if no record
    # is found.
    def third!
      third || raise_record_not_found_exception!
    end

    # Find the fourth record.
    # If no order is defined it will order by primary key.
    #
    #   Person.fourth # returns the fourth object fetched by SELECT * FROM people
    #   Person.offset(3).fourth # returns the fourth object from OFFSET 3 (which is OFFSET 6)
    #   Person.where(["user_name = :u", { u: user_name }]).fourth
    def fourth
      find_nth 3
    end

    # Same as #fourth but raises ActiveRecord::RecordNotFound if no record
    # is found.
    def fourth!
      fourth || raise_record_not_found_exception!
    end

    # Find the fifth record.
    # If no order is defined it will order by primary key.
    #
    #   Person.fifth # returns the fifth object fetched by SELECT * FROM people
    #   Person.offset(3).fifth # returns the fifth object from OFFSET 3 (which is OFFSET 7)
    #   Person.where(["user_name = :u", { u: user_name }]).fifth
    def fifth
      find_nth 4
    end

    # Same as #fifth but raises ActiveRecord::RecordNotFound if no record
    # is found.
    def fifth!
      fifth || raise_record_not_found_exception!
    end

    # Find the forty-second record. Also known as accessing "the reddit".
    # If no order is defined it will order by primary key.
    #
    #   Person.forty_two # returns the forty-second object fetched by SELECT * FROM people
    #   Person.offset(3).forty_two # returns the forty-second object from OFFSET 3 (which is OFFSET 44)
    #   Person.where(["user_name = :u", { u: user_name }]).forty_two
    def forty_two
      find_nth 41
    end

    # Same as #forty_two but raises ActiveRecord::RecordNotFound if no record
    # is found.
    def forty_two!
      forty_two || raise_record_not_found_exception!
    end

    # Find the third-to-last record.
    # If no order is defined it will order by primary key.
    #
    #   Person.third_to_last # returns the third-to-last object fetched by SELECT * FROM people
    #   Person.offset(3).third_to_last # returns the third-to-last object from OFFSET 3
    #   Person.where(["user_name = :u", { u: user_name }]).third_to_last
    def third_to_last
      find_nth_from_last 3
    end

    # Same as #third_to_last but raises ActiveRecord::RecordNotFound if no record
    # is found.
    def third_to_last!
      third_to_last || raise_record_not_found_exception!
    end

    # Find the second-to-last record.
    # If no order is defined it will order by primary key.
    #
    #   Person.second_to_last # returns the second-to-last object fetched by SELECT * FROM people
    #   Person.offset(3).second_to_last # returns the second-to-last object from OFFSET 3
    #   Person.where(["user_name = :u", { u: user_name }]).second_to_last
    def second_to_last
      find_nth_from_last 2
    end

    # Same as #second_to_last but raises ActiveRecord::RecordNotFound if no record
    # is found.
    def second_to_last!
      second_to_last || raise_record_not_found_exception!
    end

    # 如果有记录与id或条件匹配，返回true，否则返回false。参数支持6种形式：
    #
    # * Integer - 通过主键查找
    # * String - 一个主键字符串, 如'5'
    # * Array - 通过+find+风格的条件查找记录(如 <tt>['name LIKE ?', "%#{query}%"]</tt>) 
    # * Hash - 通过+find+风格的条件查找记录(如 <tt>{name: 'David'}</tt>) 
    # * +false+ - 返回false
    # * No args - 如果管理是空的，返回false，否则返回true。
    # 
    # 有关条件指定为Hash或数组的详细信息，参见ActiveRecord::Base.
    #
    # 注意：你不能传递一个字符串条件（像 <tt>name ='Jamie'</tt>）,它会被精华，然后被当作主键列。
    # 像 <tt>id = 'name = \'Jamie\''</tt>.
    #
    #   Person.exists?(5)
    #   Person.exists?('5')
    #   Person.exists?(['name LIKE ?', "%#{query}%"])
    #   Person.exists?(id: [1, 4, 8])
    #   Person.exists?(name: 'David')
    #   Person.exists?(false)
    #   Person.exists?
    #   Person.where(name: 'Spartacus', rating: 4).exists?
    def exists?(conditions = :none)
      if Base === conditions
        raise ArgumentError, <<-MSG.squish
          You are passing an instance of ActiveRecord::Base to `exists?`.
          Please pass the id of the object by calling `.id`.
        MSG
      end

      if !conditions || limit_value == 0
        return false
      else
        if eager_loading?
          relation = apply_join_dependency(eager_loading: false)
          return relation.exists?(conditions)
        else
          relation = construct_relation_for_exists(conditions)

          skip_query_cache_if_necessary { connection.select_value(relation.arel, "#{name} Exists") } ? true : false
        end

      end # .. if !conditions || limit_value == 0 .. end
    rescue ::RangeError
      false
    end

    # 每当找不到任何一个记录时(通过id，或ids)，都会调用此方法。
    # 它将引发ActiveRecord::RecordNotFound异常。
    # 
    # 错误消息取决于单个id还是提供了多个id，如果提供了多个id,则需要提供+result_size+
    # - 实际的结果数量，+expected_size+ - 预期的数量。
    def raise_record_not_found_exception!(ids = nil, result_size = nil, expected_size = nil, 
      key = primary_key, not_found_ids = nil) # :nodoc:
      conditions = arel.where_sql(@klass)
      if conditions
        conditions = " [#{conditions}]"
      end
      name = @klass.name

      if ids.nil?
        error = "Couldn't find #{name}".dup
        error << " with#{conditions}" if conditions
        raise RecordNotFound.new(error, name, key)
      elsif Array(ids).size == 1
        error = "Couldn't find #{name} with '#{key}'=#{ids}#{conditions}"
        raise RecordNotFound.new(error, name, key, ids)
      else
        error = "Couldn't find all #{name.pluralize} with '#{key}': ".dup
        error << "(#{ids.join(", ")})#{conditions} (found #{result_size} results, but was looking for #{expected_size})."
        error << " Couldn't find #{name.pluralize(not_found_ids.size)} with #{key.to_s.pluralize(not_found_ids.size)} #{not_found_ids.join(', ')}." if not_found_ids
        raise RecordNotFound.new(error, name, key, ids)
      end
    end

    private

      def offset_index
        offset_value || 0
      end

      def construct_relation_for_exists(conditions)
        relation = except(:select, :distinct, :order)._select!(ONE_AS_ONE).limit!(1)

        case conditions
        when Array, Hash
          relation.where!(conditions)
        else
          relation.where!(primary_key => conditions) unless conditions == :none
        end

        relation
      end

      def construct_join_dependency
        including = eager_load_values + includes_values
        joins = joins_values.select { |join| join.is_a?(Arel::Nodes::Join) }
        ActiveRecord::Associations::JoinDependency.new(
          klass, table, including, alias_tracker(joins)
        )
      end

      def apply_join_dependency(eager_loading: true)
        join_dependency = construct_join_dependency
        relation = except(:includes, :eager_load, :preload).joins!(join_dependency)

        if eager_loading && !using_limitable_reflections?(join_dependency.reflections)
          if has_limit_or_offset?
            limited_ids = limited_ids_for(relation)
            limited_ids.empty? ? relation.none! : relation.where!(primary_key => limited_ids)
          end
          relation.limit_value = relation.offset_value = nil
        end

        if block_given?
          relation._select!(join_dependency.aliases.columns)
          yield relation, join_dependency
        else
          relation
        end
      end

      def limited_ids_for(relation)
        values = @klass.connection.columns_for_distinct(
          connection.column_name_from_arel_node(arel_attribute(primary_key)),
          relation.order_values
        )

        relation = relation.except(:select).select(values).distinct!

        id_rows = skip_query_cache_if_necessary { @klass.connection.select_all(relation.arel, "SQL") }
        id_rows.map { |row| row[primary_key] }
      end

      def using_limitable_reflections?(reflections)
        reflections.none?(&:collection?)
      end

      # 处理find方法的返回值
      # 可以是单个，也可能是数组
      def find_with_ids(*ids)
        # 如果记录不存在主键
        if primary_key.nil?
          raise UnknownPrimaryKey.new(@klass)
        end

        # 参数为空数组
        expects_array = ids.first.kind_of?(Array)
        if expects_array && ids.first.empty?
          return ids.first
        end

        ids = ids.flatten.compact.uniq

        model_name = @klass.name

        case ids.size
        when 0
          error_message = "Couldn't find #{model_name} without an ID"
          raise RecordNotFound.new(error_message, model_name, primary_key)
        when 1
          result = find_one(ids.first)
          expects_array ? [ result ] : result
        else
          find_some(ids)
        end
      rescue ::RangeError
        error_message = "Couldn't find #{model_name} with an out of range ID"
        raise RecordNotFound.new(error_message, model_name, primary_key, ids)
      end

      def find_one(id)
        if ActiveRecord::Base === id
          raise ArgumentError, <<-MSG.squish
            You are passing an instance of ActiveRecord::Base to `find`.
            Please pass the id of the object by calling `.id`.
          MSG
        end

        relation = where(primary_key => id)
        record = relation.take

        raise_record_not_found_exception!(id, 0, 1) unless record

        record
      end

      def find_some(ids)
        return find_some_ordered(ids) unless order_values.present?

        result = where(primary_key => ids).to_a

        expected_size =
          if limit_value && ids.size > limit_value
            limit_value
          else
            ids.size
          end

        # 11 ids with limit 3, offset 9 should give 2 results.
        if offset_value && (ids.size - offset_value < expected_size)
          expected_size = ids.size - offset_value
        end

        if result.size == expected_size
          result
        else
          raise_record_not_found_exception!(ids, result.size, expected_size)
        end
      end

      def find_some_ordered(ids)
        ids = ids.slice(offset_value || 0, limit_value || ids.size) || []

        result = except(:limit, :offset).where(primary_key => ids).records

        if result.size == ids.size
          pk_type = @klass.type_for_attribute(primary_key)

          records_by_id = result.index_by(&:id)
          ids.map { |id| records_by_id.fetch(pk_type.cast(id)) }
        else
          raise_record_not_found_exception!(ids, result.size, ids.size)
        end
      end

      def find_take
        if loaded?
          records.first
        else
          @take ||= limit(1).records.first
        end
      end

      def find_take_with_limit(limit)
        if loaded?
          records.take(limit)
        else
          limit(limit).to_a
        end
      end

      def find_nth(index)
        
        @offsets[offset_index + index] ||= find_nth_with_limit(index, 1).first
      end

      def find_nth_with_limit(index, limit)
        if loaded?
          records[index, limit] || []
        else
          relation = ordered_relation

          if limit_value
            limit = [limit_value - index, limit].min
          end

          if limit > 0
            relation = relation.offset(offset_index + index) unless index.zero?
            relation.limit(limit).to_a
          else
            []
          end
        end
      end

      def find_nth_from_last(index)
        if loaded?
          records[-index]
        else
          relation = ordered_relation

          if equal?(relation) || has_limit_or_offset?
            relation.records[-index]
          else
            relation.last(index)[-index]
          end
        end
      end

      def find_last(limit)
        limit ? records.last(limit) : records.last
      end

      def ordered_relation
        
        if order_values.empty? && primary_key
          order(arel_attribute(primary_key).asc)
        else
          self
        end
      end
  end
end
