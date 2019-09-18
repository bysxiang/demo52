# frozen_string_literal: true

require "active_support/core_ext/array/extract_options"
require "action_controller/metal/mime_responds"

module ActionController #:nodoc:
  module RespondWith
    extend ActiveSupport::Concern

    included do
      class_attribute :responder, :mimes_for_respond_to
      self.responder = ActionController::Responder
      clear_respond_to
    end

    module ClassMethods
      # Defines mime types that are rendered by default when invoking
      # <tt>respond_with</tt>.
      #
      #   respond_to :html, :xml, :json
      #
      # Specifies that all actions in the controller respond to requests
      # for <tt>:html</tt>, <tt>:xml</tt> and <tt>:json</tt>.
      #
      # To specify on per-action basis, use <tt>:only</tt> and
      # <tt>:except</tt> with an array of actions or a single action:
      #
      #   respond_to :html
      #   respond_to :xml, :json, except: [ :edit ]
      #
      # This specifies that all actions respond to <tt>:html</tt>
      # and all actions except <tt>:edit</tt> respond to <tt>:xml</tt> and
      # <tt>:json</tt>.
      #
      #   respond_to :json, only: :create
      #
      # This specifies that the <tt>:create</tt> action and no other responds
      # to <tt>:json</tt>.
      def respond_to(*mimes)
        options = mimes.extract_options!

        only_actions   = Array(options.delete(:only)).map(&:to_sym)
        except_actions = Array(options.delete(:except)).map(&:to_sym)

        hash = mimes_for_respond_to.dup
        mimes.each do |mime|
          mime = mime.to_sym
          hash[mime]          = {}
          hash[mime][:only]   = only_actions   unless only_actions.empty?
          hash[mime][:except] = except_actions unless except_actions.empty?
        end
        self.mimes_for_respond_to = hash.freeze
      end

      # Clear all mime types in <tt>respond_to</tt>.
      #
      def clear_respond_to
        self.mimes_for_respond_to = Hash.new.freeze
      end
    end

    # 对于给定的控制器action，respond_with生成适当的操作响应基于客户端请求的mime
    # 类型。
    #
    # 如果仅适用资源调用该方法，则在此示例中 - 
    #
    #   class PeopleController < ApplicationController
    #     respond_to :html, :xml, :json
    #
    #     def index
    #       @people = Person.all
    #       respond_with @people
    #     end
    #   end
    #
    # 然后，响应的mime类型通常基于Accept头和声明的可用格式集，通过之前的对控制器类方法respond_to
    # 的调用。另外，可以通过在控制器显式设置request.format来选择mime类型。
    #
    # 如果没有标识可接受的格式，则应用程序返回"406 - not acceptable"状态。否则，默认的响应是
    # 程序以当前action和所选格式命名的模板。例如index.html.erb。如果没有模板可用，则使用行为
    # 视乎选择的格式而定:
    #
    #   e.g. by a +create+ action) -
    # * 对于html响应 - 如果请求方法时get，则引发异常，但对于其他请求，例如post，响应取决于资源
    #   是否有任何验证错误(即假设已尝试保持资源，例如通过+create+ action) - 
    #   1. 如果没有错误，即资源已成功保存，响应redirect到资源，即它的show action。
    #   2. If there are validation errors, the response
    #      renders a default action, which is <tt>:new</tt> for a
    #      +post+ request or <tt>:edit</tt> for +patch+ or +put+.
    #   2. 如果存在炎症错误，则为响应呈现默认action，即post请求呈现:new，patch或put请求呈现:edit
    #
    #   这样的例子
    #
    #     respond_to :html, :xml
    #
    #     def create
    #       @user = User.new(params[:user])
    #       flash[:notice] = 'User was successfully created.' if @user.save
    #       respond_with(@user)
    #     end
    #
    #   在没有create.html.erb的情况下，相当于 - 
    #
    #     def create
    #       @user = User.new(params[:user])
    #       respond_to do |format|
    #         if @user.save
    #           flash[:notice] = 'User was successfully created.'
    #           format.html { redirect_to(@user) }
    #           format.xml { render xml: @user }
    #         else
    #           format.html { render action: "new" }
    #           format.xml { render xml: @user }
    #         end
    #       end
    #     end
    #
    # * 对于JavaScript请求，- 如果找不到模板，则会抛出异常
    #
    # * 对于其他请求 - 即数据格式，如xml, json, csv等，如果传递给response_with的资源响应
    #   to_#{format}，该方法尝试一请求的格式呈现资源，例如对于xml请求，响应等同于调用
    #   render xml: resource
    #
    # === 嵌套资源(Nested resources)
    #
    # 如上所述，resources参数传递给respond_with可以扮演两个角色。对于成功的HTML请求
    # 它可用于生成重定向url(例如：create action当不存在模板)，儿用于html和JavaScript
    # 以外的格式，它是通过直接转换到所需格式(同样假设不存在模板)。
    #
    # 对于重定向成功的html请求，还支持respond_with嵌套资源的使用，其提供方式与from_for
    # 和polymorphic_url中。例如 - 
    #
    #   def create
    #     @project = Project.find(params[:project_id])
    #     @task = @project.comments.build(params[:task])
    #     flash[:notice] = 'Task was successfully created.' if @task.save
    #     respond_with(@project, @task)
    #   end
    #
    # 它将导致respond_with重定向到project_task_url而不是task_url。对于html或JavaScript
    # 以外的请求格式，如果以这种方式传递多个资源，则它是最后一个指定的被渲染的对象。
    #
    # === 自定义响应行为(Customizing response behavior)
    #
    # 与respond_to类似，respond_with也可以用一个块来调用，该块可用于覆盖任何默认
    # 响应，例如 - 
    #
    #   def create
    #     @user = User.new(params[:user])
    #     flash[:notice] = "User was successfully created." if @user.save
    #
    #     respond_with(@user) do |format|
    #       format.html { render }
    #     end
    #   end
    #
    # 传递给块的参数是ActionController::MimeResponds::Collector对象，它存储着块内定义的格式
    # 响应。注意，以这种方式显式定义响应的格式不必首先使用类方法respond_to定义。
    #
    # 此外，在指定资源之后立即传递给respond_with的hash被截石位与所有相关的一组选项格式。可以
    # 使用render接受的任何选项，例如：
    #
    #   respond_with @people, status: 200
    #
    # 但请注意，保存资源失败时，这些选项会被忽略。例如post请求之后失败了，自动渲染:new
    #
    # 三个额外的选项与respond_with有关 - 
    # 
    # 1. <tt>:location</tt> - 覆盖之后，一个post html请求成功使用的默认重定向位置
    # 2. <tt>:action</tt> - html post请求失败后，默认的呈现action
    # 3. <tt>:render</tt> - 允许将任何选项传递给:render, 当html post请求失败后调用。这是有用
    #    的，例如你需要呈现控制器路径或你之外的模板，要覆盖默认的http :status,例如：
    #
    #    respond_with(resource, render: { template: 'path/to/template', status: 422 })
    def respond_with(*resources, &block)
      if self.class.mimes_for_respond_to.empty?
        raise "In order to use respond_with, first you need to declare the " \
          "formats your controller responds to in the class level."
      end

      mimes = collect_mimes_from_class_level
      collector = ActionController::MimeResponds::Collector.new(mimes, request.variant)
      block.call(collector) if block_given?

      if format = collector.negotiate_format(request)
        _process_format(format)
        options = resources.size == 1 ? {} : resources.extract_options!
        options = options.clone
        options[:default_response] = collector.response
        (options.delete(:responder) || self.class.responder).call(self, resources, options)
      else
        raise ActionController::UnknownFormat
      end
    end

    protected

    # Before action callback that can be used to prevent requests that do not
    # match the mime types defined through <tt>respond_to</tt> from being executed.
    #
    #   class PeopleController < ApplicationController
    #     respond_to :html, :xml, :json
    #
    #     before_action :verify_requested_format!
    #   end
    def verify_requested_format!
      mimes = collect_mimes_from_class_level
      collector = ActionController::MimeResponds::Collector.new(mimes, request.variant)

      unless collector.negotiate_format(request)
        raise ActionController::UnknownFormat
      end
    end

    alias :verify_request_format! :verify_requested_format!

    # Collect mimes declared in the class method respond_to valid for the
    # current action.
    def collect_mimes_from_class_level #:nodoc:
      action = action_name.to_sym

      self.class.mimes_for_respond_to.keys.select do |mime|
        config = self.class.mimes_for_respond_to[mime]

        if config[:except]
          !config[:except].include?(action)
        elsif config[:only]
          config[:only].include?(action)
        else
          true
        end
      end
    end
  end
end
