# frozen_string_literal: true

require "zlib"
require "active_support/core_ext/array/extract_options"
require "active_support/core_ext/array/wrap"
require "active_support/core_ext/module/attribute_accessors"
require "active_support/core_ext/numeric/bytes"
require "active_support/core_ext/numeric/time"
require "active_support/core_ext/object/to_param"
require "active_support/core_ext/string/inflections"

module ActiveSupport
  # See ActiveSupport::Cache::Store for documentation.
  module Cache
    autoload :FileStore,        "active_support/cache/file_store"
    autoload :MemoryStore,      "active_support/cache/memory_store"
    autoload :MemCacheStore,    "active_support/cache/mem_cache_store"
    autoload :NullStore,        "active_support/cache/null_store"
    autoload :RedisCacheStore,  "active_support/cache/redis_cache_store"

    # These options mean something to all cache implementations. Individual cache
    # implementations may support additional options.
    UNIVERSAL_OPTIONS = [:namespace, :compress, :compress_threshold, :expires_in, :race_condition_ttl]

    module Strategy
      autoload :LocalCache, "active_support/cache/strategy/local_cache"
    end

    class << self
      # Creates a new Store object according to the given options.
      #
      # If no arguments are passed to this method, then a new
      # ActiveSupport::Cache::MemoryStore object will be returned.
      #
      # If you pass a Symbol as the first argument, then a corresponding cache
      # store class under the ActiveSupport::Cache namespace will be created.
      # For example:
      #
      #   ActiveSupport::Cache.lookup_store(:memory_store)
      #   # => returns a new ActiveSupport::Cache::MemoryStore object
      #
      #   ActiveSupport::Cache.lookup_store(:mem_cache_store)
      #   # => returns a new ActiveSupport::Cache::MemCacheStore object
      #
      # Any additional arguments will be passed to the corresponding cache store
      # class's constructor:
      #
      #   ActiveSupport::Cache.lookup_store(:file_store, '/tmp/cache')
      #   # => same as: ActiveSupport::Cache::FileStore.new('/tmp/cache')
      #
      # If the first argument is not a Symbol, then it will simply be returned:
      #
      #   ActiveSupport::Cache.lookup_store(MyOwnCacheStore.new)
      #   # => returns MyOwnCacheStore.new
      def lookup_store(*store_option)
        store, *parameters = *Array.wrap(store_option).flatten

        case store
        when Symbol
          retrieve_store_class(store).new(*parameters)
        when nil
          ActiveSupport::Cache::MemoryStore.new
        else
          store
        end
      end

      # Expands out the +key+ argument into a key that can be used for the
      # cache store. Optionally accepts a namespace, and all keys will be
      # scoped within that namespace.
      #
      # If the +key+ argument provided is an array, or responds to +to_a+, then
      # each of elements in the array will be turned into parameters/keys and
      # concatenated into a single key. For example:
      #
      #   ActiveSupport::Cache.expand_cache_key([:foo, :bar])               # => "foo/bar"
      #   ActiveSupport::Cache.expand_cache_key([:foo, :bar], "namespace")  # => "namespace/foo/bar"
      #
      # The +key+ argument can also respond to +cache_key+ or +to_param+.
      def expand_cache_key(key, namespace = nil)
        expanded_cache_key = (namespace ? "#{namespace}/" : "").dup

        if prefix = ENV["RAILS_CACHE_ID"] || ENV["RAILS_APP_VERSION"]
          expanded_cache_key << "#{prefix}/"
        end

        expanded_cache_key << retrieve_cache_key(key)
        expanded_cache_key
      end

      private
        def retrieve_cache_key(key)
          case
          when key.respond_to?(:cache_key_with_version) then key.cache_key_with_version
          when key.respond_to?(:cache_key)              then key.cache_key
          when key.is_a?(Array)                         then key.map { |element| retrieve_cache_key(element) }.to_param
          when key.respond_to?(:to_a)                   then retrieve_cache_key(key.to_a)
          else                                               key.to_param
          end.to_s
        end

        # Obtains the specified cache store class, given the name of the +store+.
        # Raises an error when the store class cannot be found.
        def retrieve_store_class(store)
          # require_relative cannot be used here because the class might be
          # provided by another gem, like redis-activesupport for example.
          require "active_support/cache/#{store}"
        rescue LoadError => e
          raise "Could not find cache store adapter for #{store} (#{e})"
        else
          ActiveSupport::Cache.const_get(store.to_s.camelize)
        end
    end

    # 这个类是缓存的抽象类。有多个缓存存储实现，每个都有自己的附加功能。参考
    # ActiveSupport::Cache模块下，例如MemCacheStore。MemCacheStore是目前最多的
    # 大型网站的热门存储产品。
    #
    # 某些实现可能不支持基本缓存之外的所有方法
    # (除：fetch, writer, read, exists和delete)
    #
    # Store能够存储所有可序列号的Ruby对象
    #
    #   cache = ActiveSupport::Cache::MemoryStore.new
    #
    #   cache.read('city')   # => nil
    #   cache.write('city', "Duckburgh")
    #   cache.read('city')   # => "Duckburgh"
    #
    # 密钥总是被翻译成字符串并区分大小写。当一个object被指定为一个键并且定义了一个
    # cache_key方法，这个将调用cache_key生成密钥，否则使用to_param方法生成。散列
    # 和数组也可用作键。该元素将由斜杠和哈希中的元素分割，将按键排序，以便保持它们
    # 一致.
    #
    #   cache.read('city') == cache.read(:city)   # => true
    #
    # Nil值可以被缓存。
    # 
    # 如果你的缓存位于共享基础结构上，则可以定义为缓存条目定义命名空间。如果定义了命名空间
    # ，它将作为每个键的前缀。命名空间可以是静态值，也可以是Proc。如果它是Proc，它将在每个
    # 键被评估时调用，以便你可以使用它来使密钥无效。
    #
    #   cache.namespace = -> { @last_mod_time }  # 为变量设置命名空间
    #   @last_mod_time = Time.now  # 这间接改变了命名空间，整个缓存将无效
    #
    # 默认情况下，压缩大于1KB的缓存数据。要关闭它，可以传递compress: false给初始化器或
    # 是fetch或write方法调用。1KB压缩的阈值可以通过:compress_threshold选项配置，单位
    # 是字节。
    class Store
      cattr_accessor :logger, instance_writer: true

      attr_reader :silence, :options
      alias :silence? :silence

      class << self
        private
          def retrieve_pool_options(options)
            {}.tap do |pool_options|
              pool_options[:size] = options.delete(:pool_size) if options[:pool_size]
              pool_options[:timeout] = options.delete(:pool_timeout) if options[:pool_timeout]
            end
          end

          def ensure_connection_pool_added!
            require "connection_pool"
          rescue LoadError => e
            $stderr.puts "You don't have connection_pool installed in your application. Please add it to your Gemfile and run bundle install"
            raise e
          end
      end

      # 创建一个新的cache。除了:namespace(它用于设置全局缓存的命名空间)，
      # options将传递给任何write方法调用
      def initialize(options = nil)
        @options = options ? options.dup : {}
      end

      # 使logger安静
      def silence!
        @silence = true
        self
      end

      # 使logger在一个块中安静
      def mute
        previous_silence, @silence = defined?(@silence) && @silence, true
        yield
      ensure
        @silence = previous_silence
      end

      # 使用给定密钥从缓存中获取数据。如果key对应存在缓存，然后返回数据。
      #
      # 如果缓存中没有这样的数据(缓存未命中)，那么将返回nil。但是，如果传递了一个块，那么
      # 将会在缓存未命中时执行。而且返回值，将会被存储到键上。
      #
      #   cache.write('today', 'Monday')
      #   cache.fetch('today')  # => "Monday"
      #
      #   cache.fetch('city')   # => nil
      #   cache.fetch('city') do
      #     'Duckburgh'
      #   end
      #   cache.fetch('city')   # => "Duckburgh"
      #
      # 您还可以通过options参数指定其他选项。设置force: true强制缓存miss，这意味着
      # 即使缓存存在也会丢失。通过传递一个块指定force: true时，这导致缓存总是写入。
      #
      #   cache.write('today', 'Monday')
      #   cache.fetch('today', force: true) { 'Tuesday' } # => 'Tuesday'
      #   cache.fetch('today', force: true) # => ArgumentError
      #
      # force选项在调用其他方法时非常有用，询问是否应该强制缓存写入。否则，就更清楚了，
      # 应该调用Cache#write方法。
      #
      # 设置compress: false，将禁用缓存压缩
      #
      # 设置expires_in将在缓存上设置到期时间。所有缓存都支持指定数量的自动过期内容，
      # 单位为秒。可以将此值指定为构造函数的选项(在这种情况下，所有条目都会受到影响),
      # 或者作为fetch或write的选项，只影响一个条目。
      #
      #   cache = ActiveSupport::Cache::MemoryStore.new(expires_in: 5.minutes)
      #   cache.write(key, value, expires_in: 1.minute) # 为一个条目设置较低的值
      #
      # 设置:version验证存储在name下的缓存是否是同一个版本。当内容不匹配时返回nil，该
      # 特性用于支持可回收的缓存键。
      #
      # 设置:race_condition_ttl在以下情况下非常有用，缓存条目经常使用且负载很重。如果
      # 一个缓存过期，由于负载过重，几个不同的进程会尝试本地读取数据然后它们都会尝试写入
      # 缓存。要避免这种情况，第一个找到过期缓存条目的进程会这样做，通过
      # :race_condition_ttl设置的值来增加缓存过期时间。是的，这个过程将过期值的时间再
      # 延长一些时间。由于前一个缓存的延长寿命，其他进程将继续使用稍微陈旧的数据稍延长一点。
      # 与此同时，第一个进程将继续，并将写入缓存新值。之后，所有进程将开始获取新值关键是
      # 保持:race_condition_ttl小。
      #
      # 如果流程重新生成条目错误，则条目将被删除，在指定的秒数后重新生成。此外，请注意
      # 过期缓存的声明只有在最近过期时才会被延长。否则生成一个新值，:race_condition_ttl
      # 不播放任何角色。
      # 
      #   # Set all values to expire after one minute.
      #   cache = ActiveSupport::Cache::MemoryStore.new(expires_in: 1.minute)
      #
      #   cache.write('foo', 'original value')
      #   val_1 = nil
      #   val_2 = nil
      #   sleep 60
      #
      #   Thread.new do
      #     val_1 = cache.fetch('foo', race_condition_ttl: 10.seconds) do
      #       sleep 1
      #       'new value 1'
      #     end
      #   end
      #
      #   Thread.new do
      #     val_2 = cache.fetch('foo', race_condition_ttl: 10.seconds) do
      #       'new value 2'
      #     end
      #   end
      #
      #   cache.fetch('foo') # => "original value"
      #   sleep 10 # 第一个线程将缓存的生命周期延长了10s
      #   cache.fetch('foo') # => "new value 1"
      #   val_1 # => "new value 1"
      #   val_2 # => "original value"
      #
      # Other options will be handled by the specific cache store implementation.
      # Internally, #fetch calls #read_entry, and calls #write_entry on a cache
      # miss. +options+ will be passed to the #read and #write calls.
      #
      # For example, MemCacheStore's #write method supports the +:raw+
      # option, which tells the memcached server to store all values as strings.
      # We can use this option with #fetch too:
      #
      #   cache = ActiveSupport::Cache::MemCacheStore.new
      #   cache.fetch("foo", force: true, raw: true) do
      #     :bar
      #   end
      #   cache.fetch('foo') # => "bar"
      def fetch(name, options = nil)
        if block_given?
          options = merged_options(options)
          key = normalize_key(name, options)

          entry = nil
          instrument(:read, name, options) do |payload|
            if ! options[:force]
              cached_entry = read_entry(key, options)
            end
            entry = handle_expired_entry(cached_entry, key, options)
            if entry && entry.mismatched?(normalize_version(name, options))
              entry = nil
            end
            if payload
              payload[:super_operation] = :fetch
            end
            if payload
              payload[:hit] = !!entry
            end
          end # instrument .. end

          if entry
            get_entry_value(entry, name, options)
          else
            save_block_result_to_cache(name, options) { |_name| yield _name }
          end
        elsif options && options[:force]
          raise ArgumentError, "Missing block: Calling `Cache#fetch` with `force: true` requires a block."
        else
          read(name, options)
        end
      end

      # Reads data from the cache, using the given key. If there is data in
      # the cache with the given key, then that data is returned. Otherwise,
      # +nil+ is returned.
      #
      # Note, if data was written with the <tt>:expires_in<tt> or <tt>:version</tt> options,
      # both of these conditions are applied before the data is returned.
      #
      # Options are passed to the underlying cache implementation.
      def read(name, options = nil)
        options = merged_options(options)
        key     = normalize_key(name, options)
        version = normalize_version(name, options)

        instrument(:read, name, options) do |payload|
          entry = read_entry(key, options)

          if entry
            if entry.expired?
              delete_entry(key, options)
              payload[:hit] = false if payload
              nil
            elsif entry.mismatched?(version)
              payload[:hit] = false if payload
              nil
            else
              payload[:hit] = true if payload
              entry.value
            end
          else
            payload[:hit] = false if payload
            nil
          end
        end
      end

      # Reads multiple values at once from the cache. Options can be passed
      # in the last argument.
      #
      # Some cache implementation may optimize this method.
      #
      # Returns a hash mapping the names provided to the values found.
      def read_multi(*names)
        options = names.extract_options!
        options = merged_options(options)

        instrument :read_multi, names, options do |payload|
          read_multi_entries(names, options).tap do |results|
            payload[:hits] = results.keys
          end
        end
      end

      # Cache Storage API to write multiple values at once.
      def write_multi(hash, options = nil)
        options = merged_options(options)

        instrument :write_multi, hash, options do |payload|
          entries = hash.each_with_object({}) do |(name, value), memo|
            memo[normalize_key(name, options)] = Entry.new(value, options.merge(version: normalize_version(name, options)))
          end

          write_multi_entries entries, options
        end
      end

      # Fetches data from the cache, using the given keys. If there is data in
      # the cache with the given keys, then that data is returned. Otherwise,
      # the supplied block is called for each key for which there was no data,
      # and the result will be written to the cache and returned.
      # Therefore, you need to pass a block that returns the data to be written
      # to the cache. If you do not want to write the cache when the cache is
      # not found, use #read_multi.
      #
      # Options are passed to the underlying cache implementation.
      #
      # Returns a hash with the data for each of the names. For example:
      #
      #   cache.write("bim", "bam")
      #   cache.fetch_multi("bim", "unknown_key") do |key|
      #     "Fallback value for key: #{key}"
      #   end
      #   # => { "bim" => "bam",
      #   #      "unknown_key" => "Fallback value for key: unknown_key" }
      #
      def fetch_multi(*names)
        raise ArgumentError, "Missing block: `Cache#fetch_multi` requires a block." unless block_given?

        options = names.extract_options!
        options = merged_options(options)

        instrument :read_multi, names, options do |payload|
          read_multi_entries(names, options).tap do |results|
            payload[:hits] = results.keys
            payload[:super_operation] = :fetch_multi

            writes = {}

            (names - results.keys).each do |name|
              results[name] = writes[name] = yield(name)
            end

            write_multi writes, options
          end
        end
      end

      # Writes the value to the cache, with the key.
      #
      # Options are passed to the underlying cache implementation.
      def write(name, value, options = nil)
        options = merged_options(options)

        instrument(:write, name, options) do
          entry = Entry.new(value, options.merge(version: normalize_version(name, options)))
          write_entry(normalize_key(name, options), entry, options)
        end
      end

      # Deletes an entry in the cache. Returns +true+ if an entry is deleted.
      #
      # Options are passed to the underlying cache implementation.
      def delete(name, options = nil)
        options = merged_options(options)

        instrument(:delete, name) do
          delete_entry(normalize_key(name, options), options)
        end
      end

      # Returns +true+ if the cache contains an entry for the given key.
      #
      # Options are passed to the underlying cache implementation.
      def exist?(name, options = nil)
        options = merged_options(options)

        instrument(:exist?, name) do
          entry = read_entry(normalize_key(name, options), options)
          (entry && !entry.expired? && !entry.mismatched?(normalize_version(name, options))) || false
        end
      end

      # Deletes all entries with keys matching the pattern.
      #
      # Options are passed to the underlying cache implementation.
      #
      # All implementations may not support this method.
      def delete_matched(matcher, options = nil)
        raise NotImplementedError.new("#{self.class.name} does not support delete_matched")
      end

      # Increments an integer value in the cache.
      #
      # Options are passed to the underlying cache implementation.
      #
      # All implementations may not support this method.
      def increment(name, amount = 1, options = nil)
        raise NotImplementedError.new("#{self.class.name} does not support increment")
      end

      # Decrements an integer value in the cache.
      #
      # Options are passed to the underlying cache implementation.
      #
      # All implementations may not support this method.
      def decrement(name, amount = 1, options = nil)
        raise NotImplementedError.new("#{self.class.name} does not support decrement")
      end

      # Cleanups the cache by removing expired entries.
      #
      # Options are passed to the underlying cache implementation.
      #
      # All implementations may not support this method.
      def cleanup(options = nil)
        raise NotImplementedError.new("#{self.class.name} does not support cleanup")
      end

      # Clears the entire cache. Be careful with this method since it could
      # affect other processes if shared cache is being used.
      #
      # The options hash is passed to the underlying cache implementation.
      #
      # All implementations may not support this method.
      def clear(options = nil)
        raise NotImplementedError.new("#{self.class.name} does not support clear")
      end

      private
        # Adds the namespace defined in the options to a pattern designed to
        # match keys. Implementations that support delete_matched should call
        # this method to translate a pattern that matches names into one that
        # matches namespaced keys.
        def key_matcher(pattern, options) # :doc:
          prefix = options[:namespace].is_a?(Proc) ? options[:namespace].call : options[:namespace]
          if prefix
            source = pattern.source
            if source.start_with?("^")
              source = source[1, source.length]
            else
              source = ".*#{source[0, source.length]}"
            end
            Regexp.new("^#{Regexp.escape(prefix)}:#{source}", pattern.options)
          else
            pattern
          end
        end

        # Reads an entry from the cache implementation. Subclasses must implement
        # this method.
        def read_entry(key, options)
          raise NotImplementedError.new
        end

        # Writes an entry to the cache implementation. Subclasses must implement
        # this method.
        def write_entry(key, entry, options)
          raise NotImplementedError.new
        end

        # Reads multiple entries from the cache implementation. Subclasses MAY
        # implement this method.
        def read_multi_entries(names, options)
          results = {}
          names.each do |name|
            key     = normalize_key(name, options)
            version = normalize_version(name, options)
            entry   = read_entry(key, options)

            if entry
              if entry.expired?
                delete_entry(key, options)
              elsif entry.mismatched?(version)
                # Skip mismatched versions
              else
                results[name] = entry.value
              end
            end
          end
          results
        end

        # Writes multiple entries to the cache implementation. Subclasses MAY
        # implement this method.
        def write_multi_entries(hash, options)
          hash.each do |key, entry|
            write_entry key, entry, options
          end
        end

        # Deletes an entry from the cache implementation. Subclasses must
        # implement this method.
        def delete_entry(key, options)
          raise NotImplementedError.new
        end

        # Merges the default options with ones specific to a method call.
        def merged_options(call_options)
          if call_options
            options.merge(call_options)
          else
            options.dup
          end
        end

        # Expands and namespaces the cache key. May be overridden by
        # cache stores to do additional normalization.
        def normalize_key(key, options = nil)
          namespace_key expanded_key(key), options
        end

        # Prefix the key with a namespace string:
        #
        #   namespace_key 'foo', namespace: 'cache'
        #   # => 'cache:foo'
        #
        # With a namespace block:
        #
        #   namespace_key 'foo', namespace: -> { 'cache' }
        #   # => 'cache:foo'
        def namespace_key(key, options = nil)
          options = merged_options(options)
          namespace = options[:namespace]

          if namespace.respond_to?(:call)
            namespace = namespace.call
          end

          if namespace
            "#{namespace}:#{key}"
          else
            key
          end
        end

        # Expands key to be a consistent string value. Invokes +cache_key+ if
        # object responds to +cache_key+. Otherwise, +to_param+ method will be
        # called. If the key is a Hash, then keys will be sorted alphabetically.
        def expanded_key(key)
          return key.cache_key.to_s if key.respond_to?(:cache_key)

          case key
          when Array
            if key.size > 1
              key = key.collect { |element| expanded_key(element) }
            else
              key = key.first
            end
          when Hash
            key = key.sort_by { |k, _| k.to_s }.collect { |k, v| "#{k}=#{v}" }
          end

          key.to_param
        end

        def normalize_version(key, options = nil)
          (options && options[:version].try(:to_param)) || expanded_version(key)
        end

        def expanded_version(key)
          case
          when key.respond_to?(:cache_version) then key.cache_version.to_param
          when key.is_a?(Array)                then key.map { |element| expanded_version(element) }.compact.to_param
          when key.respond_to?(:to_a)          then expanded_version(key.to_a)
          end
        end

        def instrument(operation, key, options = nil)
          log { "Cache #{operation}: #{normalize_key(key, options)}#{options.blank? ? "" : " (#{options.inspect})"}" }

          payload = { key: key }
          payload.merge!(options) if options.is_a?(Hash)
          ActiveSupport::Notifications.instrument("cache_#{operation}.active_support", payload) { yield(payload) }
        end

        def log
          return unless logger && logger.debug? && !silence?
          logger.debug(yield)
        end

        def handle_expired_entry(entry, key, options)
          if entry && entry.expired?
            race_ttl = options[:race_condition_ttl].to_i
            if (race_ttl > 0) && (Time.now.to_f - entry.expires_at <= race_ttl)
              # When an entry has a positive :race_condition_ttl defined, put the stale entry back into the cache
              # for a brief period while the entry is being recalculated.
              entry.expires_at = Time.now + race_ttl
              write_entry(key, entry, expires_in: race_ttl * 2)
            else
              delete_entry(key, options)
            end
            entry = nil
          end
          entry
        end

        def get_entry_value(entry, name, options)
          instrument(:fetch_hit, name, options) {}
          entry.value
        end

        def save_block_result_to_cache(name, options)
          result = instrument(:generate, name, options) do
            yield(name)
          end

          write(name, result, options)
          result
        end
    end

    # This class is used to represent cache entries. Cache entries have a value, an optional
    # expiration time, and an optional version. The expiration time is used to support the :race_condition_ttl option
    # on the cache. The version is used to support the :version option on the cache for rejecting
    # mismatches.
    #
    # Since cache entries in most instances will be serialized, the internals of this class are highly optimized
    # using short instance variable names that are lazily defined.
    class Entry # :nodoc:
      attr_reader :version

      DEFAULT_COMPRESS_LIMIT = 1.kilobyte

      # Creates a new cache entry for the specified value. Options supported are
      # +:compress+, +:compress_threshold+, +:version+ and +:expires_in+.
      def initialize(value, compress: true, compress_threshold: DEFAULT_COMPRESS_LIMIT, version: nil, expires_in: nil, **)
        @value      = value
        @version    = version
        @created_at = Time.now.to_f
        @expires_in = expires_in && expires_in.to_f

        compress!(compress_threshold) if compress
      end

      def value
        compressed? ? uncompress(@value) : @value
      end

      def mismatched?(version)
        @version && version && @version != version
      end

      # Checks if the entry is expired. The +expires_in+ parameter can override
      # the value set when the entry was created.
      def expired?
        @expires_in && @created_at + @expires_in <= Time.now.to_f
      end

      def expires_at
        @expires_in ? @created_at + @expires_in : nil
      end

      def expires_at=(value)
        if value
          @expires_in = value.to_f - @created_at
        else
          @expires_in = nil
        end
      end

      # Returns the size of the cached value. This could be less than
      # <tt>value.size</tt> if the data is compressed.
      def size
        case value
        when NilClass
          0
        when String
          @value.bytesize
        else
          @s ||= Marshal.dump(@value).bytesize
        end
      end

      # Duplicates the value in a class. This is used by cache implementations that don't natively
      # serialize entries to protect against accidental cache modifications.
      def dup_value!
        if @value && !compressed? && !(@value.is_a?(Numeric) || @value == true || @value == false)
          if @value.is_a?(String)
            @value = @value.dup
          else
            @value = Marshal.load(Marshal.dump(@value))
          end
        end
      end

      private
        def compress!(compress_threshold)
          case @value
          when nil, true, false, Numeric
            uncompressed_size = 0
          when String
            uncompressed_size = @value.bytesize
          else
            serialized = Marshal.dump(@value)
            uncompressed_size = serialized.bytesize
          end

          if uncompressed_size >= compress_threshold
            serialized ||= Marshal.dump(@value)
            compressed = Zlib::Deflate.deflate(serialized)

            if compressed.bytesize < uncompressed_size
              @value = compressed
              @compressed = true
            end
          end
        end

        def compressed?
          defined?(@compressed)
        end

        def uncompress(value)
          Marshal.load(Zlib::Inflate.inflate(value))
        end
    end
  end
end
