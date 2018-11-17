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
      # 大多数的模板依赖性可以从模板本身中的呈现调用中派生出来。下面是一些缓存调用的示例，这些缓存调用
      # 知道如何解码：
      #
      #   render partial: "comments/comment", collection: commentable.comments
      #   render "comments/comments"
      #   render 'comments/comments'
      #   render('comments/comments')
      #
      #   render "header" 转换为 render("comments/header")
      #
      #   render(@topic)         translates to render("topics/topic")
      #   render(topics)         translates to render("topics/topic")
      #   render(message.topics) translates to render("topics/topic")
      #
      # 但是，不可能像这样派生所有的渲染调用。以下是一些无法得出的例子：
      #
      #   render group_of_attachments
      #   render @project.documents.where(published: true).order('created_at')
      #
      # 您必须重写为这样：
      #
      #   render partial: 'attachments/attachment', collection: group_of_attachments
      #   render partial: 'documents/document', collection: @project.documents.where(published: true).order('created_at')
      #
      # === 显式依赖
      #
      # 有时您将拥有根本无法派生的模板依赖项。当您在帮助程序中进行模板渲染时，通常会出现这种情况。
      # 这是一个例子:
      #
      #   <%= render_sortable_todolists @project.todolists %>
      #
      # 你需要特殊注释格式来调用它们：
      #
      #   <%# Template Dependency: todolists/todolist %>
      #   <%= render_sortable_todolists @project.todolists %>
      #
      # 在某些情况下，比如单表继承设置，您可能有一堆显式依赖关系。而不是把每个模板都写出来
      # ，您可以使用通配符匹配目录中的任何模板。
      #
      #   <%# Template Dependency: events/* %>
      #   <%= render_categorizable_events @person.events %>
      #
      # 这会将目录中的每个模板标记为依赖项。找到那些模板，通配符必须从app/views或路径中绝对定义
      # ，否则添加prepend_view_path或append_view_path。这样，app/views/recordings/evetns的
      # 通配符将使recordings/events/*
      #
      # 用于匹配显示依赖项的正则匹配是/# Template Dependency: (\S+)/，因此将其输入为正确的
      # 非常重要。每行只能声明一个模板依赖项。
      #
      # === 外部依赖关系
      #
      # 如果您使用辅助方法，例如，在缓存块内部，然后你更新了那个帮助器，您也必须碰撞缓存。
      # 它是如何做的并不重要，但模板文件的MD5必须改变。一个建议是在注释中准确表达(这样文件MD5就改变了)，
      # 例如：
      #
      #   <%# Helper Dependency Updated: May 6, 2012 at 6pm %>
      #   <%= some_helper_method(person) %>
      #
      # 现在，您要做的就是在辅助方法更改时更改该时间戳。
      #
      # === 集合缓存
      #
      # 渲染每个使用相同部分的对象集合时，可以传递cached: true选项。
      #
      # 对于渲染的集合
      #
      #   <%= render partial: 'projects/project', collection: @projects, cached: true %>
      #
      # 上述代码中所有的缓存模板一次性获取，速度更快。
      #
      # 此外，尚未缓存的模板也会写入缓存，在下次渲染时获取。
      #
      # 与单个模板片段缓存一起使用非常好。例如，如果集合呈现的模板缓存如下：
      #
      #   # projects/_project.html.erb
      #   <% cache project do %>
      #     <%# ... %>
      #   <% end %>
      #
      # 任何集合渲染都会在尝试时找到这些缓存的模板，一次读取多个模板。
      #
      # 如果你的集合缓存依赖于多个源(尽量避免这样做以保持简单)，您可以将所有这些依赖项命名为返回
      # 数据的块的一部分
      #
      #   <%= render partial: 'projects/project', collection: @projects, cached: -> project { [ project, current_user ] } %>
      #
      # 这将包括两个记录作为缓存键的一部分，并且更新它们中的任何一个将使缓存过期。
      #
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
