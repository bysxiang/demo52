# frozen_string_literal: true

module ActiveRecord
  module Batches
    class BatchEnumerator
      include Enumerable

      def initialize(of: 1000, start: nil, finish: nil, relation:) #:nodoc:
        @of       = of
        @relation = relation
        @start = start
        @finish = finish
      end

      # 循环遍历数据中的记录集合(例如，使用+all+方法)是非常低效的，因为它会尝试
      # 一次实例化所有对象。
      #
      # 在这种情况下，批处理方法允许你使用批量记录(batches records)，从而大大减少内存消耗。
      #
      #   Person.in_batches.each_record do |person|
      #     person.do_awesome_stuff
      #   end
      #
      #   Person.where("age > 21").in_batches(of: 10).each_record do |person|
      #     person.party_all_night!
      #   end
      #
      # 如果你不提供一个块，将返回Enumerator对象，你可以使用它来继续链式操作：
      #
      #   Person.in_batches.each_record.with_index do |person, index|
      #     person.award_trophy(index + 1)
      #   end
      def each_record
        if ! block_given?
          to_enum(:each_record)
        else
          @relation.to_enum(:in_batches, of: @of, start: @start, finish: @finish, load: true).each do |relation|
            relation.records.each { |record| yield record }
          end
        end
      end

      # Delegates #delete_all, #update_all, #destroy_all methods to each batch.
      #
      #   People.in_batches.delete_all
      #   People.where('age < 10').in_batches.destroy_all
      #   People.in_batches.update_all('age = age + 1')
      [:delete_all, :update_all, :destroy_all].each do |method|
        define_method(method) do |*args, &block|
          @relation.to_enum(:in_batches, of: @of, start: @start, finish: @finish, load: false).each do |relation|
            relation.send(method, *args, &block)
          end
        end
      end

      # Yields an ActiveRecord::Relation object for each batch of records.
      #
      #   Person.in_batches.each do |relation|
      #     relation.update_all(awesome: true)
      #   end
      def each
        enum = @relation.to_enum(:in_batches, of: @of, start: @start, finish: @finish, load: false)
        return enum.each { |relation| yield relation } if block_given?
        enum
      end
    end
  end
end
