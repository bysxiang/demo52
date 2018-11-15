# frozen_string_literal: true

module ActionView
  # = Action View Cache Helper
  module Helpers #:nodoc:
    module CacheHelper
      # 这个帮助程序公开了一种用于缓存视图片段的方法，而不是整个action或页面。
      # 这种技术很有用，缓存诸如菜单，新主题列表，静态HTML之类的内容碎片，等等，
      # 此方法采用包含的块，来缓存内容。 
      # 
      # 最好的方法是使用可循环的基于键的缓存过期的Memcached或Redis之上，它会自动运行踢出旧
      # 条目。
      #
      # 当使用这个方法时，您将缓存依赖项列为缓存的名称，如下所示：
      #
      #   <% cache project do %>
      #     <b>All the topics on this project</b>
      #     <%= render project.topics %>
      #   <% end %>
      #
      # 这种方法将假设当添加新主题时，您将触摸到这个项目。此调用生成的缓存如下：
      #
      #   views/template/action.html.erb:7a1156131a6928cb0026877f8b749ac9/projects/123
      #         ^template path           ^template tree digest            ^class   ^id
      #
      #
      # 这个缓存键是稳定的，但它与从项目派生的缓存版本相结合记录。当修改project的update_at时，+cache_version+
      # 甚至会改变，如果key保持稳定。这意味着与传统的基于密钥的缓存过期方法不同，你不会生成缓存垃圾，未使用的密钥，
      # 只是因为一来记录已更新。
      #
      # 如果模板缓存依赖于多个源(为了简单起见，尽量避免这种情况)，你可以将这些依赖项命名为数组的一部分:
      #
      #   <% cache [ project, current_user ] do %>
      #     <b>All the topics on this project</b>
      #     <%= render project.topics %>
      #   <% end %>
      #
      # 这将包括两个记录作为缓存键的一部分，并且更新它们中的任何一个将使缓存过期。
      #
      # ==== \Template digest
      # 
      # 添加到模板键上的模板摘要通过对整个模板文件的内容进行MD5计算。这确保当您更改模板文件时，您的缓存
      # 自动过期。
      #
      # 注意MD5是取整个模板文件，而不仅仅是取缓存do/end调用中的内容。因此，在调用之外更改某些内容仍然有可能
      # 使缓存过期。
      #
      # 此外，digestor将自动检查模板文件中显式依赖和隐式依赖，并将它们包括在摘要中：
      #
      # 通过传递skip_digest: true可以跳过digestor 
      #
      #   <% cache project, skip_digest: true do %>
      #     <b>All the topics on this project</b>
      #     <%= render project.topics %>
      #   <% end %>
      #
      # ==== 隐式依赖关系
      #
      # Most template dependencies can be derived from calls to render in the template itself.
      # Here are some examples of render calls that Cache Digests knows how to decode:
      #
      #   render partial: "comments/comment", collection: commentable.comments
      #   render "comments/comments"
      #   render 'comments/comments'
      #   render('comments/comments')
      #
      #   render "header" translates to render("comments/header")
      #
      #   render(@topic)         translates to render("topics/topic")
      #   render(topics)         translates to render("topics/topic")
      #   render(message.topics) translates to render("topics/topic")
      #
      # It's not possible to derive all render calls like that, though.
      # Here are a few examples of things that can't be derived:
      #
      #   render group_of_attachments
      #   render @project.documents.where(published: true).order('created_at')
      #
      # You will have to rewrite those to the explicit form:
      #
      #   render partial: 'attachments/attachment', collection: group_of_attachments
      #   render partial: 'documents/document', collection: @project.documents.where(published: true).order('created_at')
      #
      # === Explicit dependencies
      #
      # Sometimes you'll have template dependencies that can't be derived at all. This is typically
      # the case when you have template rendering that happens in helpers. Here's an example:
      #
      #   <%= render_sortable_todolists @project.todolists %>
      #
      # You'll need to use a special comment format to call those out:
      #
      #   <%# Template Dependency: todolists/todolist %>
      #   <%= render_sortable_todolists @project.todolists %>
      #
      # In some cases, like a single table inheritance setup, you might have
      # a bunch of explicit dependencies. Instead of writing every template out,
      # you can use a wildcard to match any template in a directory:
      #
      #   <%# Template Dependency: events/* %>
      #   <%= render_categorizable_events @person.events %>
      #
      # This marks every template in the directory as a dependency. To find those
      # templates, the wildcard path must be absolutely defined from <tt>app/views</tt> or paths
      # otherwise added with +prepend_view_path+ or +append_view_path+.
      # This way the wildcard for <tt>app/views/recordings/events</tt> would be <tt>recordings/events/*</tt> etc.
      #
      # The pattern used to match explicit dependencies is <tt>/# Template Dependency: (\S+)/</tt>,
      # so it's important that you type it out just so.
      # You can only declare one template dependency per line.
      #
      # === External dependencies
      #
      # If you use a helper method, for example, inside a cached block and
      # you then update that helper, you'll have to bump the cache as well.
      # It doesn't really matter how you do it, but the MD5 of the template file
      # must change. One recommendation is to simply be explicit in a comment, like:
      #
      #   <%# Helper Dependency Updated: May 6, 2012 at 6pm %>
      #   <%= some_helper_method(person) %>
      #
      # Now all you have to do is change that timestamp when the helper method changes.
      #
      # === Collection Caching
      #
      # When rendering a collection of objects that each use the same partial, a <tt>:cached</tt>
      # option can be passed.
      #
      # For collections rendered such:
      #
      #   <%= render partial: 'projects/project', collection: @projects, cached: true %>
      #
      # The <tt>cached: true</tt> will make Action View's rendering read several templates
      # from cache at once instead of one call per template.
      #
      # Templates in the collection not already cached are written to cache.
      #
      # Works great alongside individual template fragment caching.
      # For instance if the template the collection renders is cached like:
      #
      #   # projects/_project.html.erb
      #   <% cache project do %>
      #     <%# ... %>
      #   <% end %>
      #
      # Any collection renders will find those cached templates when attempting
      # to read multiple templates at once.
      #
      # If your collection cache depends on multiple sources (try to avoid this to keep things simple),
      # you can name all these dependencies as part of a block that returns an array:
      #
      #   <%= render partial: 'projects/project', collection: @projects, cached: -> project { [ project, current_user ] } %>
      #
      # This will include both records as part of the cache key and updating either of them will
      # expire the cache.
      def cache(name = {}, options = {}, &block)
        if controller.respond_to?(:perform_caching) && controller.perform_caching
          name_options = options.slice(:skip_digest, :virtual_path)
          safe_concat(fragment_for(cache_fragment_name(name, name_options), options, &block))
        else
          yield
        end

        nil
      end

      # Cache fragments of a view if +condition+ is true
      #
      #   <% cache_if admin?, project do %>
      #     <b>All the topics on this project</b>
      #     <%= render project.topics %>
      #   <% end %>
      def cache_if(condition, name = {}, options = {}, &block)
        if condition
          cache(name, options, &block)
        else
          yield
        end

        nil
      end

      # Cache fragments of a view unless +condition+ is true
      #
      #   <% cache_unless admin?, project do %>
      #     <b>All the topics on this project</b>
      #     <%= render project.topics %>
      #   <% end %>
      def cache_unless(condition, name = {}, options = {}, &block)
        cache_if !condition, name, options, &block
      end

      # This helper returns the name of a cache key for a given fragment cache
      # call. By supplying +skip_digest:+ true to cache, the digestion of cache
      # fragments can be manually bypassed. This is useful when cache fragments
      # cannot be manually expired unless you know the exact key which is the
      # case when using memcached.
      #
      # The digest will be generated using +virtual_path:+ if it is provided.
      #
      def cache_fragment_name(name = {}, skip_digest: nil, virtual_path: nil)
        if skip_digest
          name
        else
          fragment_name_with_digest(name, virtual_path)
        end
      end

    private

      def fragment_name_with_digest(name, virtual_path)
        virtual_path ||= @virtual_path

        if virtual_path
          name = controller.url_for(name).split("://").last if name.is_a?(Hash)

          if digest = Digestor.digest(name: virtual_path, finder: lookup_context, dependencies: view_cache_dependencies).presence
            [ "#{virtual_path}:#{digest}", name ]
          else
            [ virtual_path, name ]
          end
        else
          name
        end
      end

      def fragment_for(name = {}, options = nil, &block)
        if content = read_fragment_for(name, options)
          @view_renderer.cache_hits[@virtual_path] = :hit if defined?(@view_renderer)
          content
        else
          @view_renderer.cache_hits[@virtual_path] = :miss if defined?(@view_renderer)
          write_fragment_for(name, options, &block)
        end
      end

      def read_fragment_for(name, options)
        controller.read_fragment(name, options)
      end

      def write_fragment_for(name, options)
        pos = output_buffer.length
        yield
        output_safe = output_buffer.html_safe?
        fragment = output_buffer.slice!(pos..-1)
        if output_safe
          self.output_buffer = output_buffer.class.new(output_buffer)
        end
        controller.write_fragment(name, fragment, options)
      end
    end
  end
end
