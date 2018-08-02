# frozen_string_literal: true

require "active_record/relation/from_clause"
require "active_record/relation/query_attribute"
require "active_record/relation/where_clause"
require "active_record/relation/where_clause_factory"
require "active_model/forbidden_attributes_protection"

module ActiveRecord
  module QueryMethods
    extend ActiveSupport::Concern

    # 用于检查params是否permit
    include ActiveModel::ForbiddenAttributesProtection

    # WhereChain对象充当#where没有参数时的查询占位符。在这种情况下，#where必须链式调用#not以返回新的relation
    # 对象
    # 这个类专门处理where not的
    class WhereChain
      include ActiveModel::ForbiddenAttributesProtection

      # scope通常是Relation实例的副本
      def initialize(scope)
        @scope = scope
      end

      # 返回一个表示where not条件的新关系
      #
      # #not接收的条件可以是一个String, array或hash。详见 QueryMethods#where 格式部分。
      #
      #    User.where.not("name = 'Jon'")
      #    # SELECT * FROM users WHERE NOT (name = 'Jon')
      #
      #    User.where.not(["name = ?", "Jon"])
      #    # SELECT * FROM users WHERE NOT (name = 'Jon')
      #
      #    User.where.not(name: "Jon")
      #    # SELECT * FROM users WHERE name != 'Jon'
      #
      #    User.where.not(name: nil)
      #    # SELECT * FROM users WHERE name IS NOT NULL
      #
      #    User.where.not(name: %w(Ko1 Nobu))
      #    # SELECT * FROM users WHERE name NOT IN ('Ko1', 'Nobu')
      #
      #    User.where.not(name: "Jon", role: "admin")
      #    # SELECT * FROM users WHERE name != 'Jon' AND role != 'admin'
      def not(opts, *rest)
        opts = sanitize_forbidden_attributes(opts)

        where_clause = @scope.send(:where_clause_factory).build(opts, rest)

        @scope.references!(PredicateBuilder.references(opts)) if Hash === opts
        @scope.where_clause += where_clause.invert
        @scope
      end
    end # class WhereChain .. end

    FROZEN_EMPTY_ARRAY = [].freeze
    FROZEN_EMPTY_HASH = {}.freeze

    Relation::VALUE_METHODS.each do |name|
      method_name = \
        case name
        when *Relation::MULTI_VALUE_METHODS then "#{name}_values"
        when *Relation::SINGLE_VALUE_METHODS then "#{name}_value"
        when *Relation::CLAUSE_METHODS then "#{name}_clause"
        end
      class_eval <<-CODE, __FILE__, __LINE__ + 1
        def #{method_name}                   # def includes_values
          get_value(#{name.inspect})         #   get_value(:includes)
        end                                  # end

        def #{method_name}=(value)           # def includes_values=(value)
          set_value(#{name.inspect}, value)  #   set_value(:includes, value)
        end                                  # end
      CODE
    end

    alias extensions extending_values

    # 指定要包含在结果集中的关系. 
    # 例子：
    #
    #   users = User.includes(:address)
    #   users.each do |user|
    #     user.address.city
    #   end
    #
    # 允许你访问User模型的address属性，而不会触发其他查询。与简单的join相比，这回带来
    # 性能提升
    #
    # 你也可以指定多个关系，像这样：
    #
    #   users = User.includes(:address, :friends)
    #
    # 使用Hash可以加载嵌套关系：
    #
    #   users = User.includes(:address, friends: [:address, :followers])
    #
    # === conditions
    #
    # 如果你想为included的模型添加条件，你需要明确的引用它们。例子：
    #
    #   User.includes(:posts).where('posts.name = ?', 'example')
    #
    # 会抛出错误，但这会有效：
    #
    #   User.includes(:posts).where('posts.name = ?', 'example').references(:posts)
    # 
    # 请注意，#includes与#references需要使用关联名称 - 实际的表名
    def includes(*args)
      check_if_method_has_arguments!(:includes, args)
      spawn.includes!(*args)
    end

    # 将表名数组添加到self.includes_values中
    def includes!(*args) # :nodoc:
      args.reject!(&:blank?)
      args.flatten!

      self.includes_values |= args
      self
    end

    # 通过在+args+上执行left outer join强制执行加载：
    #
    #   User.eager_load(:posts)
    #   # SELECT "users"."id" AS t0_r0, "users"."name" AS t0_r1, ...
    #   # FROM "users" LEFT OUTER JOIN "posts" ON "posts"."user_id" =
    #   # "users"."id"
    def eager_load(*args)
      check_if_method_has_arguments!(:eager_load, args)
      spawn.eager_load!(*args)
    end

    def eager_load!(*args) # :nodoc:
      self.eager_load_values += args
      self
    end

    # 允许预加载+args+，与+includes+一样
    #
    #   User.preload(:posts)
    #   # SELECT "posts".* FROM "posts" WHERE "posts"."user_id" IN (1, 2, 3)
    def preload(*args)
      check_if_method_has_arguments!(:preload, args)
      spawn.preload!(*args)
    end

    def preload!(*args) # :nodoc:
      self.preload_values += args
      self
    end

    # 用于指示给定的+table_names+由sql字符串引用，因此应该在任何查询中加入而不是单独加载。
    # 此方法仅与+includes+一起使用。有关详细信息，请参阅#includes。
    #
    #   User.includes(:posts).where("posts.name = 'foo'")
    #   # 不会join posts表，所以它会导致错误。
    #
    #   User.includes(:posts).where("posts.name = 'foo'").references(:posts)
    #   # 查询现在知道引用了posts表，所以它添加了JOIN关联。
    def references(*table_names)
      check_if_method_has_arguments!(:references, table_names)
      spawn.references!(*table_names)
    end

    # 将表添加到self.references_values
    def references!(*table_names) # :nodoc:
      table_names.flatten!
      table_names.map!(&:to_s)

      self.references_values |= table_names
      self
    end

    # 以两种不同额方式工作。
    #
    # 首先：使用一个块，这样它就可以像<tt>Array#select</tt>一样使用。
    #
    #   Model.all.select { |m| m.field == value }
    #
    # 这将从数据库中为作用域构建一个对象数组，把将它转换为数组并使用它们迭代它们使用
    # <tt>Array#select</tt>.
    #
    # 第二：修改查询的select语句，以便只确定字段被检索：
    #
    #   Model.select(:field)
    #   # => [#<Model id: nil, field: "value">]
    #
    # 虽然在上面的例子中看起来好像这个方法返回了一个数组，它实际上返回了一个relation对象，可以有其他
    # 附加的查询方法，例如ActiveRecord::QueryMethods中的其他查询方法。
    #
    # 参数可以是字段数组。可变长度参数
    #
    #   Model.select(:field, :other_field, :and_one_more)
    #   # => [#<Model id: nil, field: "value", other_field: "value", and_one_more: "value">]
    #
    # 你还可以使用一个或多个字符串，这些字符串将作为select参数保持不变。
    #
    #   Model.select('field AS field_one', 'other_field AS field_two')
    #   # => [#<Model id: nil, field: "value", other_field: "value">]
    #
    # 如果指定了别名，则可以从结果对象访问它：
    #
    #   Model.select('field AS field_one').first.field_one
    #   # => "value"
    #
    # 访问没有select选择的字段对象的属性，除了id外，都将抛出ActiveModel::MissingAttributeError 异常
    #
    #   Model.select(:field).first.other_field
    #   # => ActiveModel::MissingAttributeError: missing attribute: other_field
    def select(*fields)
      if block_given?
        if fields.any?
          raise ArgumentError, "`select' with block doesn't take arguments."
        end

        return super()
      else
        if fields.empty?
          raise ArgumentError, "Call `select' with at least one field"
        end

        spawn._select!(*fields)
      end
    end

    def _select!(*fields) # :nodoc:
      fields.flatten!
      fields.map! do |field|
        klass.attribute_alias?(field) ? klass.attribute_alias(field).to_sym : field
      end
      self.select_values += fields
      self
    end

    # 允许指定一个分组属性：
    #
    #   User.group(:name)
    #   # SELECT "users".* FROM "users" GROUP BY name
    #
    # 返回一个基于group属性分组的具有不同记录的数组
    #
    #   User.select([:id, :name])
    #   # => [#<User id: 1, name: "Oscar">, #<User id: 2, name: "Oscar">, #<User id: 3, name: "Foo">]
    #
    #   User.group(:name)
    #   # => [#<User id: 3, name: "Foo", ...>, #<User id: 2, name: "Oscar", ...>]
    #
    #   User.group('name AS grouped_name, age')
    #   # => [#<User id: 3, name: "Foo", age: 21, ...>, #<User id: 2, name: "Oscar", age: 21, ...>, #<User id: 5, name: "Foo", age: 23, ...>]
    #
    # 支持将一组属性传递给group by
    #
    #   User.select([:id, :first_name]).group(:id, :first_name).first(3)
    #   # => [#<User id: 1, first_name: "Bill">, #<User id: 2, first_name: "Earl">, #<User id: 3, first_name: "Beto">]
    def group(*args)
      check_if_method_has_arguments!(:group, args)
      spawn.group!(*args)
    end

    def group!(*args) # :nodoc:
      args.flatten!

      self.group_values += args
      self
    end

    # 允许你指定order属性：
    #
    #   User.order(:name)
    #   # SELECT "users".* FROM "users" ORDER BY "users"."name" ASC
    #
    #   User.order(email: :desc)
    #   # SELECT "users".* FROM "users" ORDER BY "users"."email" DESC
    #
    #   User.order(:name, email: :desc)
    #   # SELECT "users".* FROM "users" ORDER BY "users"."name" ASC, "users"."email" DESC
    #
    #   User.order('name')
    #   # SELECT "users".* FROM "users" ORDER BY name
    #
    #   User.order('name DESC')
    #   # SELECT "users".* FROM "users" ORDER BY name DESC
    #
    #   User.order('name DESC, email')
    #   # SELECT "users".* FROM "users" ORDER BY name DESC, email
    def order(*args)
      check_if_method_has_arguments!(:order, args)
      spawn.order!(*args)
    end

    # 与#order一样，但在relation上操作而不是复制
    # 多个order调用，会合并在一起，组成order多个字段
    def order!(*args) # :nodoc:
      preprocess_order_args(args)

      self.order_values += args1
      self
    end

    # 替换已存在的order定义。
    #
    #   User.order('email DESC').reorder('id ASC') # generated SQL has 'ORDER BY id ASC'
    #
    # 随后将对相同关系的order进行追加。例如：
    # 
    #   User.order('email DESC').reorder('id ASC').order('name ASC')
    #
    # 生成查询如 'ORDER BY id ASC, name ASC'.
    def reorder(*args)
      check_if_method_has_arguments!(:reorder, args)
      spawn.reorder!(*args)
    end

    # 与#reorder不同，它是在relation对象上运行而不是复制
    def reorder!(*args) # :nodoc:
      preprocess_order_args(args)

      self.reordering_value = true
      self.order_values = args
      self
    end

    VALID_UNSCOPING_VALUES = Set.new([:where, :select, :group, :order, :lock,
                                     :limit, :offset, :joins, :left_outer_joins,
                                     :includes, :from, :readonly, :having])

    # 删除已在关系链上定义的不需要的关系。当传递关系链并且想要时，这很有用，修改关系而不是
    # 删除重建。
    #
    #   User.order('email DESC').unscope(:order) == User.all
    #
    # 方法参数时对应于方法名称的符号，有效参数在VALID_UNSCOPING_VALUES中给出。也可以使用多个参数
    # 调用此方法。
    #
    #   User.order('email DESC').select('id').where(name: "John")
    #       .unscope(:order, :select, :where) == User.all
    #
    # 还可以将散列作为参数传递给unscope指定+:where+的具体值。这是通过传递具有单个键值对的散列来完成的。
    # 关键之键值对是应该unscope的。例如：
    #
    #   User.where(name: "John", active: true).unscope(where: :name)
    #       == User.where(active: true)
    #
    # This method is similar to #except, but unlike
    # #except, it persists across merges:
    #
    #   User.order('email').merge(User.except(:order))
    #       == User.order('email')
    #
    #   User.order('email').merge(User.unscope(:order))
    #       == User.all
    #
    # This means it can be used in association definitions:
    #
    #   has_many :comments, -> { unscope(where: :trashed) }
    #
    def unscope(*args)
      check_if_method_has_arguments!(:unscope, args)
      spawn.unscope!(*args)
    end

    def unscope!(*args) # :nodoc:
      args.flatten!
      self.unscope_values += args

      args.each do |scope|
        case scope
        when Symbol
          scope = :left_outer_joins if scope == :left_joins
          if !VALID_UNSCOPING_VALUES.include?(scope)
            raise ArgumentError, "Called unscope() with invalid unscoping argument ':#{scope}'. Valid arguments are :#{VALID_UNSCOPING_VALUES.to_a.join(", :")}."
          end
          set_value(scope, DEFAULT_VALUES[scope])
        when Hash
          scope.each do |key, target_value|
            if key != :where
              raise ArgumentError, "Hash arguments in .unscope(*args) must have :where as the key."
            end

            target_values = Array(target_value).map(&:to_s)
            self.where_clause = where_clause.except(*target_values)
          end
        else
          raise ArgumentError, "Unrecognized scoping: #{args.inspect}. Use .unscope(where: :attribute_name) or .unscope(:order), for example."
        end
      end

      self
    end

    # 在+args+参数上执行join。给定的符号比U匹配一个关联的名称。 
    #
    #   User.joins(:posts)
    #   # SELECT "users".*
    #   # FROM "users"
    #   # INNER JOIN "posts" ON "posts"."user_id" = "users"."id"
    #
    # Multiple joins:
    #
    #   User.joins(:posts, :account)
    #   # SELECT "users".*
    #   # FROM "users"
    #   # INNER JOIN "posts" ON "posts"."user_id" = "users"."id"
    #   # INNER JOIN "accounts" ON "accounts"."id" = "users"."account_id"
    #
    # Nested joins:
    #
    #   User.joins(posts: [:comments])
    #   # SELECT "users".*
    #   # FROM "users"
    #   # INNER JOIN "posts" ON "posts"."user_id" = "users"."id"
    #   # INNER JOIN "comments" "comments_posts"
    #   #   ON "comments_posts"."post_id" = "posts"."id"
    #
    # 你能够使用字符串来自定义join:
    #
    #   User.joins("LEFT JOIN bookmarks ON bookmarks.bookmarkable_type = 'Post' AND bookmarks.user_id = users.id")
    #   # SELECT "users".* FROM "users" LEFT JOIN bookmarks ON bookmarks.bookmarkable_type = 'Post' AND bookmarks.user_id = users.id
    def joins(*args)
      check_if_method_has_arguments!(:joins, args)
      spawn.joins!(*args)
    end

    def joins!(*args) # :nodoc:
      args.compact!
      args.flatten!
      self.joins_values += args
      self
    end

    # 执行一个左外连接
    #
    #   User.left_outer_joins(:posts)
    #   => SELECT "users".* FROM "users" LEFT OUTER JOIN "posts" ON "posts"."user_id" = "users"."id"
    #
    def left_outer_joins(*args)
      check_if_method_has_arguments!(__callee__, args)
      spawn.left_outer_joins!(*args)
    end
    alias :left_joins :left_outer_joins

    def left_outer_joins!(*args) # :nodoc:
      args.compact!
      args.flatten!
      self.left_outer_joins_values += args
      self
    end

    # 返回一个关系对象，这是根据条件过滤后的结果
    #
    # #where接收多种格式的条件。在下面的例子中，结果给我了一个说明。不同的适配器查询可能不同。
    #
    # === string
    #
    # 没有附加参数的单个字符串传递给查询。作为SQL片段的构造函数，并在查询的where子句中使用。
    #
    #    Client.where("orders_count = '2'")
    #    # SELECT * from clients where orders_count = '2';
    #
    # 注意，从用户输入的构建自己的字符串可能会暴露给应用程序。如果没有正确地进行防注入攻击。作为
    # 另一种选择，建议使用下列方法之一。
    #
    # === array
    #
    # 如果传递数组，则将数组的第一个元素视为模板，将其余元素插入到模板中以生成条件。
    # ActiveRecord负责构建查询以避免注入攻击，并将Ruby类型转换到需要的数据库类型，
    # 插入元素按它们出现的顺序排列到字符串中。
    #
    #   User.where(["name = ? and email = ?", "Joe", "joe@example.com"])
    #   # SELECT * FROM users WHERE name = 'Joe' AND email = 'joe@example.com';
    #
    # 或者，你可以在模板中使用命名占位符，并将Hash传递为第二个元素。模板中的名称用相应的名称替换。
    #
    #   User.where(["name = :name and email = :email", { name: "Joe", email: "joe@example.com" }])
    #   # SELECT * FROM users WHERE name = 'Joe' AND email = 'joe@example.com';
    #
    # 这可以在复杂查询中产生更多可读代码。
    #
    # 最后，可以在模板中使用sprintf风格的模板。这有点儿不同，与以前的方法相比，您负责确保模板中的值正确引用，
    # 这些值传递给连接器用于引用，但调用方负责确保它们包含在生成的sql中的引文中。引用后，使用Kernel::sprintf
    # 转义插入值。 所以%d将生成数字，最终生成值，调用方自己确保
    #
    #   User.where(["name = '%s' and email = '%s'", "Joe", "joe@example.com"])
    #   # SELECT * FROM users WHERE name = 'Joe' AND email = 'joe@example.com';
    #
    # 如果用多个参数调用，则将它们视为单个数组的元素。
    #
    #   User.where("name = :name and email = :email", { name: "Joe", email: "joe@example.com" })
    #   # SELECT * FROM users WHERE name = 'Joe' AND email = 'joe@example.com';
    #
    # 当使用字符串指定条件时，可以使用任何数据库中的操作符。虽然这很灵活，但这也会在无意之间引入与数据库的依赖
    # 关系。如果您的代码是面向消费者的，使用多个数据库后端进行测试。
    #
    # === hash
    #
    # #where也接收hash条件，键是字段而值时要搜索的值。
    #
    # 字段可以是符号或字符串。值可以是单个值，数组或范围。
    #
    #    User.where({ name: "Joe", email: "joe@example.com" })
    #    # SELECT * FROM users WHERE name = 'Joe' AND email = 'joe@example.com'
    #
    #    User.where({ name: ["Alice", "Bob"]})
    #    # SELECT * FROM users WHERE name IN ('Alice', 'Bob')
    #
    #    User.where({ created_at: (Time.now.midnight - 1.day)..Time.now.midnight })
    #    # SELECT * FROM users WHERE (created_at BETWEEN '2012-06-09 07:00:00.000000' AND '2012-06-10 07:00:00.000000')
    #
    # 在belongs_to关系的情况下，可以将值指定为模型名称，它会自动转换。
    #
    #    author = Author.find(1)
    #
    #    # 以下查询是等效的
    #    Post.where(author: author)
    #    Post.where(author_id: author)
    #
    # 这也适用于多态的belongs_to关联：
    #
    #    treasure = Treasure.create(name: 'gold coins')
    #    treasure.price_estimates << PriceEstimate.create(price: 125)
    #
    #    # 以下查询将是等效的
    #    PriceEstimate.where(estimate_of: treasure)
    #    PriceEstimate.where(estimate_of_type: 'Treasure', estimate_of_id: treasure)
    #
    # === Joins
    #
    # 如果关系是join的结果，则可以创建任何使用创建连接的条件的表。对于字符串和数组条件，请在条件中使用
    # 表名。
    #
    #    User.joins(:posts).where("posts.created_at < ?", Time.now)
    #
    # 对于Hash条件，你可以使用表名，也可以使用子哈希
    #
    #    User.joins(:posts).where({ "posts.published" => true })
    #    User.joins(:posts).where({ posts: { published: true } })
    #
    # === no argument
    # 
    # 如果没有传递任何参数, 此方法将返回一个WhereChain实例，可以链式调用#not以返回一个否则
    # where子句的关系对象
    #
    #    User.where.not(name: "Jon")
    #    # SELECT * FROM users WHERE name != 'Jon'
    #
    # 更多详细信息详见 WhereChain #not 方法.
    #
    # === blank condition
    #
    # 如果条件是空白对象，则#where方法不做操作返回当前relation对象
    def where(opts = :chain, *rest)
      if :chain == opts
        WhereChain.new(spawn)
      elsif opts.blank?
        self
      else
        spawn.where!(opts, *rest)
      end
    end

    def where!(opts, *rest) # :nodoc:
      opts = sanitize_forbidden_attributes(opts)
      references!(PredicateBuilder.references(opts)) if Hash === opts
      self.where_clause += where_clause_factory.build(opts, rest)
      self
    end

    # 允许用现在的给定属性条件覆盖先前的where给定属性
    #
    #   Post.where(trashed: true).where(trashed: false)
    #   # WHERE `trashed` = 1 AND `trashed` = 0
    #
    #   Post.where(trashed: true).rewhere(trashed: false)
    #   # WHERE `trashed` = 0
    #
    #   Post.where(active: true).where(trashed: true).rewhere(trashed: false)
    #   # WHERE `active` = 1 AND `trashed` = 0
    #
    # 这是unscope().where的简写形式。与reorder不同，我们只是取消了指定字段的条件-而不是整个where语句。
    def rewhere(conditions)
      unscope(where: conditions.keys).where(conditions)
    end

    # 返回一个新的relation，它是这个relation与传递的relation的逻辑结合。
    #
    # 这两种relation必须在结构上兼容：必须是一个模型，必须只根据where(如果没有定义#group)或只使用having(如果定义了
    # #group)。这两个relation 没有使用#limit, #offset或distinct集合。
    #
    #    Post.where("id = 1").or(Post.where("author_id = 3"))
    #    # SELECT `posts`.* FROM `posts` WHERE ((id = 1) OR (author_id = 3))
    #
    def or(other)
      unless other.is_a? Relation
        raise ArgumentError, "You have passed #{other.class.name} object to #or. Pass an ActiveRecord::Relation object instead."
      end

      spawn.or!(other)
    end

    def or!(other) # :nodoc:
      incompatible_values = structurally_incompatible_values_for_or(other)

      unless incompatible_values.empty?
        raise ArgumentError, "Relation passed to #or must be structurally compatible. Incompatible values: #{incompatible_values}"
      end

      self.where_clause = self.where_clause.or(other.where_clause)
      self.having_clause = having_clause.or(other.having_clause)
      self.references_values += other.references_values

      self
    end

    # 允许指定HAVING子句。注意，使用它必须同时使用GROUP子句。
    #
    #   Order.having('SUM(price) > 30').group('user_id')
    def having(opts, *rest)
      opts.blank? ? self : spawn.having!(opts, *rest)
    end

    def having!(opts, *rest) # :nodoc:
      opts = sanitize_forbidden_attributes(opts)
      references!(PredicateBuilder.references(opts)) if Hash === opts

      self.having_clause += having_clause_factory.build(opts, rest)
      self
    end

    # 指定要检索记录数量的语句。
    #
    #   User.limit(10) # generated SQL has 'LIMIT 10'
    #
    #   User.limit(10).limit(20) # generated SQL has 'LIMIT 20'
    def limit(value)
      spawn.limit!(value)
    end

    def limit!(value) # :nodoc:
      self.limit_value = value
      self
    end

    # 指定在返回之前跳过的行数。
    #
    #   User.offset(10) # generated SQL has "OFFSET 10"
    #
    # 应该与order一起使用。
    #
    #   User.offset(10).order("name ASC")
    def offset(value)
      spawn.offset!(value)
    end

    def offset!(value) # :nodoc:
      self.offset_value = value
      self
    end

    # 指定锁定设置。更多信息，查看ActiveRecord::Locking.
    def lock(locks = true)
      spawn.lock!(locks)
    end

    def lock!(locks = true) # :nodoc:
      case locks
      when String, TrueClass, NilClass
        self.lock_value = locks || true
      else
        self.lock_value = false
      end

      self
    end

    # 返回一个具有0条记录的可链式操作的relation对象。
    #
    # 返回的relation对象实现Null对象模式。它是一个对象，具有定义的null行为并返回一个
    # 空数组，不查询数据库记录。
    #
    # 链接到空关系的对象上的任何条件将继续产生空关系对象，不会向数据库发出任何查询。
    #
    # 它适用于方法或scope返回空对象但需要结果是可链式操作。
    #
    # For example:
    #
    #   @posts = current_user.visible_posts.where(name: params[:name])
    #   # 这个visible_posts应该返回一个可链式操作的Relation对象
    #
    #   def visible_posts
    #     case role
    #     when 'Country Manager'
    #       Post.where(country: country)
    #     when 'Reviewer'
    #       Post.published
    #     when 'Bad User'
    #       Post.none # It can't be chained if [] is returned.
    #     end
    #   end
    #
    def none
      spawn.none!
    end

    def none! # :nodoc:
      where!("1=0").extending!(NullRelation)
    end

    # 为返回的关系设置只读属性。如果value为true(默认值)，尝试更新记录将导致错误。
    #
    #   users = User.readonly
    #   users.first.save
    #   => ActiveRecord::ReadOnlyRecord: User is marked as readonly
    def readonly(value = true)
      spawn.readonly!(value)
    end

    def readonly!(value = true) # :nodoc:
      self.readonly_value = value
      self
    end

    # Sets attributes to be used when creating new records from a
    # relation object.
    #
    # 为从一个新对象中创建relation对象设置属性
    #
    #   users = User.where(name: 'Oscar')
    #   users.new.name # => 'Oscar'
    #
    #   users = users.create_with(name: 'DHH')
    #   users.new.name # => 'DHH'
    #
    # 你可以给#create_with传递+nil+重置属性：
    #
    #   users = users.create_with(nil)
    #   users.new.name # => 'Oscar'
    def create_with(value)
      spawn.create_with!(value)
    end

    def create_with!(value) # :nodoc:
      if value
        value = sanitize_forbidden_attributes(value)
        self.create_with_value = create_with_value.merge(value)
      else
        self.create_with_value = FROZEN_EMPTY_HASH
      end

      self
    end

    # Specifies table from which the records will be fetched. For example:
    # 即指定子查询的from。
    # 指定将从中获取记录的表。例如：
    #
    #   Topic.select('title').from('posts')
    #   # SELECT title FROM post
    #
    # 可以接受其他关系对象。例如：
    #
    #   Topic.select('title').from(Topic.approved)
    #   # SELECT title FROM (SELECT * FROM topics WHERE approved = 't') subquery
    #
    #   Topic.select('a.title').from(Topic.approved, :a)
    #   # SELECT a.title FROM (SELECT * FROM topics WHERE approved = 't') a
    #
    def from(value, subquery_name = nil)
      spawn.from!(value, subquery_name)
    end

    def from!(value, subquery_name = nil) # :nodoc:
      self.from_clause = Relation::FromClause.new(value, subquery_name)
      self
    end

    # 指定记录是否应该是唯一的。例如：
    #
    #   User.select(:name)
    #   # 可能返回两个同名记录
    #
    #   User.select(:name).distinct
    #   # 每个不同名称返回一条记录
    #
    #   User.select(:name).distinct.distinct(false)
    #   # 你可以删除唯一性
    def distinct(value = true)
      spawn.distinct!(value)
    end

    # 与#distinct不同，在对象上修改。
    def distinct!(value = true) # :nodoc:
      self.distinct_value = value
      self
    end

    #用于通道一个模块或一个块为scope添加一些方法。
    #
    # 返回的对象时一个relation对象，可以进一步扩展。
    #
    # === 使用一个模块
    #
    #   module Pagination
    #     def page(number)
    #       # pagination code goes here
    #     end
    #   end
    #
    #   scope = Model.all.extending(Pagination)
    #   scope.page(params[:page])
    #
    # 你也可以传递一个模块列表(多个模块)
    #
    #   scope = Model.all.extending(Pagination, SomethingElse)
    #
    # === 使用一个块
    #
    #   scope = Model.all.extending do
    #     def page(number)
    #       # pagination code goes here
    #     end
    #   end
    #   scope.page(params[:page])
    #
    # 你也可以同时使用块和模块列表进行继承扩展：
    #
    #   scope = Model.all.extending(Pagination) do
    #     def per_page(number)
    #       # pagination code goes here
    #     end
    #   end
    def extending(*modules, &block)
      if modules.any? || block
        spawn.extending!(*modules, &block)
      else
        self
      end
    end

    def extending!(*modules, &block) # :nodoc:
      modules << Module.new(&block) if block
      modules.flatten!

      self.extending_values += modules
      extend(*extending_values) if extending_values.any?

      self
    end

    # 颠倒关系的排序，如ASC转为DESC
    #
    #   User.order('name ASC').reverse_order # generated SQL has 'ORDER BY name DESC'
    def reverse_order
      spawn.reverse_order!
    end

    def reverse_order! # :nodoc:
      orders = order_values.uniq
      orders.reject!(&:blank?)
      self.order_values = reverse_sql_order(orders)
      self
    end

    def skip_query_cache! # :nodoc:
      self.skip_query_cache_value = true
      self
    end

    # 返回与relation关联的Arel对象。
    def arel(aliases = nil) # :nodoc:
      @arel ||= build_arel(aliases)
    end

    protected
      # Returns a relation value with a given name
      def get_value(name) # :nodoc:
        @values.fetch(name, DEFAULT_VALUES[name])
      end

      # Sets the relation value with the given name
      def set_value(name, value) # :nodoc:
        assert_mutability!
        @values[name] = value
      end

    private

      def assert_mutability!
        raise ImmutableRelation if @loaded
        raise ImmutableRelation if defined?(@arel) && @arel
      end

      def build_arel(aliases)
        arel = Arel::SelectManager.new(table)

        aliases = build_joins(arel, joins_values.flatten, aliases) unless joins_values.empty?
        build_left_outer_joins(arel, left_outer_joins_values.flatten, aliases) unless left_outer_joins_values.empty?

        arel.where(where_clause.ast) unless where_clause.empty?
        arel.having(having_clause.ast) unless having_clause.empty?
        if limit_value
          limit_attribute = ActiveModel::Attribute.with_cast_value(
            "LIMIT".freeze,
            connection.sanitize_limit(limit_value),
            Type.default_value,
          )
          arel.take(Arel::Nodes::BindParam.new(limit_attribute))
        end
        if offset_value
          offset_attribute = ActiveModel::Attribute.with_cast_value(
            "OFFSET".freeze,
            offset_value.to_i,
            Type.default_value,
          )
          arel.skip(Arel::Nodes::BindParam.new(offset_attribute))
        end
        arel.group(*arel_columns(group_values.uniq.reject(&:blank?))) unless group_values.empty?

        build_order(arel)

        build_select(arel)

        arel.distinct(distinct_value)
        arel.from(build_from) unless from_clause.empty?
        arel.lock(lock_value) if lock_value

        arel
      end

      def build_from
        opts = from_clause.value
        name = from_clause.name
        case opts
        when Relation
          if opts.eager_loading?
            opts = opts.send(:apply_join_dependency)
          end
          name ||= "subquery"
          opts.arel.as(name.to_s)
        else
          opts
        end
      end

      def build_left_outer_joins(manager, outer_joins, aliases)
        buckets = outer_joins.group_by do |join|
          case join
          when Hash, Symbol, Array
            :association_join
          when ActiveRecord::Associations::JoinDependency
            :stashed_join
          else
            raise ArgumentError, "only Hash, Symbol and Array are allowed"
          end
        end

        build_join_query(manager, buckets, Arel::Nodes::OuterJoin, aliases)
      end

      def build_joins(manager, joins, aliases)
        buckets = joins.group_by do |join|
          case join
          when String
            :string_join
          when Hash, Symbol, Array
            :association_join
          when ActiveRecord::Associations::JoinDependency
            :stashed_join
          when Arel::Nodes::Join
            :join_node
          else
            raise "unknown class: %s" % join.class.name
          end
        end

        build_join_query(manager, buckets, Arel::Nodes::InnerJoin, aliases)
      end

      def build_join_query(manager, buckets, join_type, aliases)
        buckets.default = []

        association_joins         = buckets[:association_join]
        stashed_association_joins = buckets[:stashed_join]
        join_nodes                = buckets[:join_node].uniq
        string_joins              = buckets[:string_join].map(&:strip).uniq

        join_list = join_nodes + convert_join_strings_to_ast(string_joins)
        alias_tracker = alias_tracker(join_list, aliases)

        join_dependency = ActiveRecord::Associations::JoinDependency.new(
          klass, table, association_joins, alias_tracker
        )

        joins = join_dependency.join_constraints(stashed_association_joins, join_type)
        joins.each { |join| manager.from(join) }

        manager.join_sources.concat(join_list)

        alias_tracker.aliases
      end

      def convert_join_strings_to_ast(joins)
        joins
          .flatten
          .reject(&:blank?)
          .map { |join| table.create_string_join(Arel.sql(join)) }
      end

      def build_select(arel)
        if select_values.any?
          arel.project(*arel_columns(select_values.uniq))
        elsif klass.ignored_columns.any?
          arel.project(*klass.column_names.map { |field| arel_attribute(field) })
        else
          arel.project(table[Arel.star])
        end
      end

      def arel_columns(columns)
        columns.map do |field|
          if (Symbol === field || String === field) && (klass.has_attribute?(field) || klass.attribute_alias?(field)) && !from_clause.value
            arel_attribute(field)
          elsif Symbol === field
            connection.quote_table_name(field.to_s)
          else
            field
          end
        end
      end

      def reverse_sql_order(order_query)
        if order_query.empty?
          return [arel_attribute(primary_key).desc] if primary_key
          raise IrreversibleOrderError,
            "Relation has no current order and table has no primary key to be used as default order"
        end

        order_query.flat_map do |o|
          case o
          when Arel::Attribute
            o.desc
          when Arel::Nodes::Ordering
            o.reverse
          when String
            if does_not_support_reverse?(o)
              raise IrreversibleOrderError, "Order #{o.inspect} can not be reversed automatically"
            end
            o.split(",").map! do |s|
              s.strip!
              s.gsub!(/\sasc\Z/i, " DESC") || s.gsub!(/\sdesc\Z/i, " ASC") || (s << " DESC")
            end
          else
            o
          end
        end
      end

      def does_not_support_reverse?(order)
        # Account for String subclasses like Arel::Nodes::SqlLiteral that
        # override methods like #count.
        order = String.new(order) unless order.instance_of?(String)

        # Uses SQL function with multiple arguments.
        (order.include?(",") && order.split(",").find { |section| section.count("(") != section.count(")") }) ||
          # Uses "nulls first" like construction.
          /nulls (first|last)\Z/i.match?(order)
      end

      def build_order(arel)
        orders = order_values.uniq
        orders.reject!(&:blank?)

        arel.order(*orders) unless orders.empty?
      end

      VALID_DIRECTIONS = [:asc, :desc, :ASC, :DESC,
                          "asc", "desc", "ASC", "DESC"].to_set # :nodoc:

      def validate_order_args(args)
        args.each do |arg|
          next unless arg.is_a?(Hash)
          arg.each do |_key, value|
            unless VALID_DIRECTIONS.include?(value)
              raise ArgumentError,
                "Direction \"#{value}\" is invalid. Valid directions are: #{VALID_DIRECTIONS.to_a.inspect}"
            end
          end
        end
      end

      def preprocess_order_args(order_args)
        order_args.map! do |arg|
          klass.sanitize_sql_for_order(arg)
        end
        order_args.flatten!

        @klass.enforce_raw_sql_whitelist(
          order_args.flat_map { |a| a.is_a?(Hash) ? a.keys : a },
          whitelist: AttributeMethods::ClassMethods::COLUMN_NAME_ORDER_WHITELIST
        )

        validate_order_args(order_args)

        references = order_args.grep(String)
        references.map! { |arg| arg =~ /^\W?(\w+)\W?\./ && $1 }.compact!
        references!(references) if references.any?

        # if a symbol is given we prepend the quoted table name
        order_args.map! do |arg|
          case arg
          when Symbol
            arel_attribute(arg).asc
          when Hash
            arg.map { |field, dir|
              case field
              when Arel::Nodes::SqlLiteral
                field.send(dir.downcase)
              else
                arel_attribute(field).send(dir.downcase)
              end
            }
          else
            arg
          end
        end.flatten!
      end

      # Checks to make sure that the arguments are not blank. Note that if some
      # blank-like object were initially passed into the query method, then this
      # method will not raise an error.
      #
      # Example:
      #
      #    Post.references()   # raises an error
      #    Post.references([]) # does not raise an error
      #
      # This particular method should be called with a method_name and the args
      # passed into that method as an input. For example:
      #
      # def references(*args)
      #   check_if_method_has_arguments!("references", args)
      #   ...
      # end
      def check_if_method_has_arguments!(method_name, args)
        if args.blank?
          raise ArgumentError, "The method .#{method_name}() must contain arguments."
        end
      end

      STRUCTURAL_OR_METHODS = Relation::VALUE_METHODS - [:extending, :where, :having, :unscope, :references]
      def structurally_incompatible_values_for_or(other)
        STRUCTURAL_OR_METHODS.reject do |method|
          get_value(method) == other.get_value(method)
        end
      end

      def where_clause_factory
        @where_clause_factory ||= Relation::WhereClauseFactory.new(klass, predicate_builder)
      end
      alias having_clause_factory where_clause_factory

      DEFAULT_VALUES = {
        create_with: FROZEN_EMPTY_HASH,
        where: Relation::WhereClause.empty,
        having: Relation::WhereClause.empty,
        from: Relation::FromClause.empty
      }

      Relation::MULTI_VALUE_METHODS.each do |value|
        DEFAULT_VALUES[value] ||= FROZEN_EMPTY_ARRAY
      end
  end
end
