# frozen_string_literal: true

module AbstractController
  module Caching
    # 片段缓存用于缓存内部的各种块。视图不缓存整个action作为一个整体,
    # 这是因为action通常会经常变化，而某些片段却不怎么变化，这样可多方
    # 共享。可使用ActionView::Helpers::CacheHelper来操作。
    #
    # 尽管强烈建议使用基于键的缓存过期(详见CacheHelper)，但同样可以手动
    # 终止缓存。例如:
    #
    #   expire_fragment('name_of_cache')
    module Fragments
      extend ActiveSupport::Concern

      included do
        if respond_to?(:class_attribute)
          class_attribute :fragment_cache_keys
        else
          mattr_writer :fragment_cache_keys
        end

        self.fragment_cache_keys = []

        if respond_to?(:helper_method)
          helper_method :fragment_cache_key
          helper_method :combined_fragment_cache_key
        end
      end

      module ClassMethods
        # 允许指定控制器范围的键前缀的缓存片段。传递一个常量+value+, 或一个快
        # ，每次生成缓存键时都会计算一个值。
        #
        # 例如，您可能希望为所有片段缓存键添加前缀，使用全局版本标识符，你可以轻松
        # 实现使所有缓存无效。
        #
        #   class ApplicationController
        #     fragment_cache_key "v1"
        #   end
        #
        # 什么时候让所有片段无效，只需更改字符串常量。或者，逐步展开缓存，
        # 使用计算值的失效
        #
        #   class ApplicationController
        #     fragment_cache_key do
        #       @account.id.odd? ? "v1" : "v2"
        #     end
        #   end
        def fragment_cache_key(value = nil, &key)
          self.fragment_cache_keys += [key || -> { value }]
        end
      end # ClassMethods .. end

      # Given a key (as described in +expire_fragment+), returns
      # a key suitable for use in reading, writing, or expiring a
      # cached fragment. All keys begin with <tt>views/</tt>,
      # followed by any controller-wide key prefix values, ending
      # with the specified +key+ value. The key is expanded using
      # ActiveSupport::Cache.expand_cache_key.
      def fragment_cache_key(key)
        ActiveSupport::Deprecation.warn(<<-MSG.squish)
          Calling fragment_cache_key directly is deprecated and will be removed in Rails 6.0.
          All fragment accessors now use the combined_fragment_cache_key method that retains the key as an array,
          such that the caching stores can interrogate the parts for cache versions used in
          recyclable cache keys.
        MSG

        head = self.class.fragment_cache_keys.map { |k| instance_exec(&k) }
        tail = key.is_a?(Hash) ? url_for(key).split("://").last : key
        ActiveSupport::Cache.expand_cache_key([*head, *tail], :views)
      end

      # 给定一个键(如+expire_fragment+所述)，返回适合于读取，写入或过期的缓存片段。
      # 所有键以:views开始，然后是ENV["RAILS_CACHE_ID"]或ENV["RAILS_APP_VERSION"]
      # ，然后是任何控制器范围的键前缀，结束部分是指定的 +key+值。
      def combined_fragment_cache_key(key)
        head = self.class.fragment_cache_keys.map { |k| instance_exec(&k) }
        tail = key.is_a?(Hash) ? url_for(key).split("://").last : key
        [ :views, (ENV["RAILS_CACHE_ID"] || ENV["RAILS_APP_VERSION"]), *head, *tail ].compact
      end

      # Writes +content+ to the location signified by
      # +key+ (see +expire_fragment+ for acceptable formats).
      def write_fragment(key, content, options = nil)
        return content unless cache_configured?

        key = combined_fragment_cache_key(key)
        instrument_fragment_cache :write_fragment, key do
          content = content.to_str
          cache_store.write(key, content, options)
        end
        content
      end

      # Reads a cached fragment from the location signified by +key+
      # (see +expire_fragment+ for acceptable formats).
      def read_fragment(key, options = nil)
        if cache_configured?
          key = combined_fragment_cache_key(key)
          instrument_fragment_cache :read_fragment, key do
            result = cache_store.read(key, options)
            result.respond_to?(:html_safe) ? result.html_safe : result
          end
        end
      end

      # Check if a cached fragment from the location signified by
      # +key+ exists (see +expire_fragment+ for acceptable formats).
      def fragment_exist?(key, options = nil)
        return unless cache_configured?
        key = combined_fragment_cache_key(key)

        instrument_fragment_cache :exist_fragment?, key do
          cache_store.exist?(key, options)
        end
      end

      # 从缓存中移除片段
      #
      # +key+有3种形式：
      #
      # * String - 这通常是路径的形式，像<tt>pages/45/notes</tt>.
      # * Hash - 作为对+url_for+的隐式调用，像 
      #   <tt>{ controller: 'pages', action: 'notes', id: 45}</tt>
      # * Regexp - 将移除所有匹配的片段，所以,
      #   <tt>%r{pages/\d*/notes}</tt> 将移除所有notes.确保不要在正则表达式中
      #   使用锚点(<tt>^</tt> or <tt>$</tt>),因为实际匹配的文件名是这样的
      #   <tt>./cache/filename/path.cache</tt>. Regexp过期形式仅在可以遍历
      #   所有键(与memcached不同)的缓存上受支持。
      #
      # +options+ 用于传递给+delete+方法(或+delete_matched+方法，Regexp 键时)
      def expire_fragment(key, options = nil)
        if cache_configured?
          if ! key.is_a?(Regexp)
            key = combined_fragment_cache_key(key)
          end

          instrument_fragment_cache :expire_fragment, key do
            if key.is_a?(Regexp)
              cache_store.delete_matched(key, options)
            else
              cache_store.delete(key, options)
            end
          end
        end
        
      end

      def instrument_fragment_cache(name, key) # :nodoc:
        ActiveSupport::Notifications.instrument("#{name}.#{instrument_name}", instrument_payload(key)) { yield }
      end
    end
  end
end
