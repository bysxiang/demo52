# frozen_string_literal: true

require "active_record/relation/batches/batch_enumerator"

module ActiveRecord
  module Batches
    ORDER_IGNORE_MESSAGE = "Scoped order is ignored, it's forced to be batch order."

    # 循环访问数据库的记录集合(例如使用Scoping::Named::ClassMethods.all方法)
    # 这非常低效，因为它尝试同时实例化所有对象。
    #
    # 在这种情况下，batch方法允许你处理批量记录，而且大大减少内存消耗。
    #
    # #find_each方法使用#find_in_batches，批大小为1000(或通过+:batch_size+选项指定)
    #
    #   Person.find_each do |person|
    #     person.do_awesome_stuff
    #   end
    #
    #   Person.where("age > 21").find_each do |person|
    #     person.party_all_night!
    #   end
    #
    # 如果没有提供一个块，将返回一个Enumerator对象，后续可以链式遍历
    #
    #   Person.find_each.with_index do |person, index|
    #     person.award_trophy(index + 1)
    #   end
    #
    # ==== Options
    # * <tt>:batch_size</tt> - 指定批大小。默认1000.
    # * <tt>:start</tt> - 指定开始的主键值
    # * <tt>:finish</tt> - 指定结束的主键值
    # * <tt>:error_on_ignore</tt> - 覆盖应用程序中的配置。是引发错误还是忽略。
    #
    # limit会被尊重，如果存在的化，则不会考虑batch size，它可以小于、等于或大于
    # batch_size。
    #
    # 如果你愿意，选项+start+和+finish+特比有用，多个工作者处理相同的处理队列。
    # 你可以worker1处理id 1..9999，worker2处理10000以上的记录。
    #
    #   # In worker 1, let's process until 9999 records.
    #   Person.find_each(finish: 9_999) do |person|
    #     person.party_all_night!
    #   end
    #
    #   # In worker 2, let's process from record 10_000 and onwards.
    #   Person.find_each(start: 10_000) do |person|
    #     person.party_all_night!
    #   end
    #
    # 注意：无法设置ordder。这是自动设置为主键("id ASC")以进行批量排序工作。这也意味着此方法
    # 仅在主键存在时才能有效排序。(可以是数字、字符串)
    #
    # 注意：按其性质，批处理以竞态条件为准，如果其他进程正在修改数据库。
    def find_each(start: nil, finish: nil, batch_size: 1000, error_on_ignore: nil)
      if block_given?
        find_in_batches(start: start, finish: finish, batch_size: batch_size, error_on_ignore: error_on_ignore) do |records|
          records.each { |record| yield record }
        end
      else
        enum_for(:find_each, start: start, finish: finish, batch_size: batch_size, error_on_ignore: error_on_ignore) do
          relation = self
          apply_limits(relation, start, finish).size
        end
      end
    end

    # 生成由查找选项作为数组找到的批处理记录。
    #
    #   Person.where("age > 21").find_in_batches do |group|
    #     sleep(50) # Make sure it doesn't get too crowded in there!
    #     group.each { |person| person.party_all_night! }
    #   end
    #
    # 如果没有为#find_in_batches提供一个块，它将返回一个Enumerator对象以链式操作：
    #
    #   Person.find_in_batches.with_index do |group, batch|
    #     puts "Processing group ##{batch}"
    #     group.each(&:recover_from_last_night!)
    #   end
    #
    # 要逐个yield每个记录，使用#find_each替代。
    #
    # ==== Options
    # * <tt>:batch_size</tt> - 指定批大小。默认1000.
    # * <tt>:start</tt> - 指定开始的主键值
    # * <tt>:finish</tt> - 指定结束的主键值
    # * <tt>:error_on_ignore</tt> - 覆盖应用程序中的配置。是引发错误还是忽略。
    #
    # limit会被尊重，如果存在的化，则不会考虑batch size，它可以小于、等于或大于
    # batch_size。
    #
    # 如果你愿意，选项+start+和+finish+特比有用，多个工作者处理相同的处理队列。
    # 你可以worker1处理id 1..9999，worker2处理10000以上的记录。
    #
    #   # Let's process from record 10_000 on.
    #   Person.find_in_batches(start: 10_000) do |group|
    #     group.each { |person| person.party_all_night! }
    #   end
    #
    # 注意：无法设置ordder。这是自动设置为主键("id ASC")以进行批量排序工作。这也意味着此方法
    # 仅在主键存在时才能有效排序。(可以是数字、字符串)
    #
    # 注意：按其性质，批处理以竞态条件为准，如果其他进程正在修改数据库。
    def find_in_batches(start: nil, finish: nil, batch_size: 1000, error_on_ignore: nil)
      relation = self

      if ! block_given?
        return to_enum(:find_in_batches, start: start, finish: finish, batch_size: batch_size, error_on_ignore: error_on_ignore) do
          total = apply_limits(relation, start, finish).size
          (total - 1).div(batch_size) + 1
        end
      end

      in_batches(of: batch_size, start: start, finish: finish, load: true, error_on_ignore: error_on_ignore) do |batch|
        yield batch.to_a
      end
    end

    # yield Relaction对象以处理一批记录。
    #
    #   Person.where("age > 21").in_batches do |relation|
    #     relation.delete_all
    #     sleep(10) # Throttle the delete queries
    #   end
    #
    # 如果你没有提供一个块，他将返回一个BatchEnumerator对象。
    #
    #   Person.in_batches.each_with_index do |relation, batch_index|
    #     puts "Processing relation ##{batch_index}"
    #     relation.delete_all
    #   end
    #
    # 再返回的额BatchEnumerator对象上调用方法的示例：
    #
    #   Person.in_batches.delete_all
    #   Person.in_batches.update_all(awesome: true)
    #   Person.in_batches.each_record(&:party_all_night!)
    #
    # ==== Options
    # * <tt>:of</tt> - 指定批大小。默认1000.
    # * <tt>:load</tt> - 指定是否应该加载关系，默认为false。
    # * <tt>:start</tt> - 指定开始的主键值
    # * <tt>:finish</tt> - 指定结束的主键值
    # * <tt>:error_on_ignore</tt> - 覆盖应用程序中的配置。是引发错误还是忽略。
    #
    # limit会被尊重，如果存在的化，则不会考虑batch size，它可以小于、等于或大于
    # batch_size。
    #
    # 如果你愿意，选项+start+和+finish+特比有用，多个工作者处理相同的处理队列。
    # 你可以worker1处理id 1..9999，worker2处理10000以上的记录。
    #
    #   # Let's process from record 10_000 on.
    #   Person.in_batches(start: 10_000).update_all(awesome: true)
    #
    # 调用关系上查询方法的示例：
    #
    #   Person.in_batches.each do |relation|
    #     relation.update_all('age = age + 1')
    #     relation.where('age > 21').update_all(should_party: true)
    #     relation.where('age <= 21').delete_all
    #   end
    #
    # 注意： 如果你要遍历每条记录，则应该调用each_record产生的BatchEnumerator上
    # 的each_record
    #
    #   Person.in_batches.each_record(&:party_all_night!)
    #
    # 注意：无法设置ordder。这是自动设置为主键("id ASC")以进行批量排序工作。这也意味着此方法
    # 仅在主键存在时才能有效排序。(可以是数字、字符串)
    #
    # 注意：按其性质，批处理以竞态条件为准，如果其他进程正在修改数据库。
    def in_batches(of: 1000, start: nil, finish: nil, load: false, error_on_ignore: nil)
      relation = self
      if ! block_given?
        return BatchEnumerator.new(of: of, start: start, finish: finish, relation: self)
      end

      if arel.orders.present?
        act_on_ignored_order(error_on_ignore)
      end

      batch_limit = of
      if limit_value
        remaining   = limit_value
        batch_limit = remaining if remaining < batch_limit
      end

      relation = relation.reorder(batch_order).limit(batch_limit)
      relation = apply_limits(relation, start, finish)
      relation.skip_query_cache! # Retaining the results in the query cache would undermine the point of batching
      batch_relation = relation

      loop do
        if load
          records = batch_relation.records
          ids = records.map(&:id)
          yielded_relation = where(primary_key => ids)
          yielded_relation.load_records(records)
        else
          ids = batch_relation.pluck(primary_key)
          yielded_relation = where(primary_key => ids)
        end

        if ! ids.empty?
          primary_key_offset = ids.last
          raise ArgumentError.new("Primary key not included in the custom select clause") unless primary_key_offset

          yield yielded_relation

          if ids.length >= batch_limit

            if limit_value
              remaining -= ids.length

              if remaining == 0
                # Saves a useless iteration when the limit is a multiple of the
                # batch size.
                break
              elsif remaining < batch_limit
                relation = relation.limit(remaining)
              end
            end

            attr = Relation::QueryAttribute.new(primary_key, primary_key_offset, klass.type_for_attribute(primary_key))
            batch_relation = relation.where(arel_attribute(primary_key).gt(Arel::Nodes::BindParam.new(attr)))
          end # if ids.length >= batch_limit .. end
        end # else ids.empty? .. end

      end # loop .. end
    end

    private

      def apply_limits(relation, start, finish)
        if start
          attr = Relation::QueryAttribute.new(primary_key, start, klass.type_for_attribute(primary_key))
          relation = relation.where(arel_attribute(primary_key).gteq(Arel::Nodes::BindParam.new(attr)))
        end
        if finish
          attr = Relation::QueryAttribute.new(primary_key, finish, klass.type_for_attribute(primary_key))
          relation = relation.where(arel_attribute(primary_key).lteq(Arel::Nodes::BindParam.new(attr)))
        end
        relation
      end

      def batch_order
        arel_attribute(primary_key).asc
      end

      def act_on_ignored_order(error_on_ignore)
        raise_error = (error_on_ignore.nil? ? klass.error_on_ignored_order : error_on_ignore)

        if raise_error
          raise ArgumentError.new(ORDER_IGNORE_MESSAGE)
        elsif logger
          logger.warn(ORDER_IGNORE_MESSAGE)
        end
      end
  end
end
