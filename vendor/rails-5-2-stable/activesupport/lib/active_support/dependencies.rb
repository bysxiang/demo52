# frozen_string_literal: true

require "set"
require "thread"
require "concurrent/map"
require "pathname"
require "active_support/core_ext/module/aliasing"
require "active_support/core_ext/module/attribute_accessors"
require "active_support/core_ext/module/introspection"
require "active_support/core_ext/module/anonymous"
require "active_support/core_ext/object/blank"
require "active_support/core_ext/kernel/reporting"
require "active_support/core_ext/load_error"
require "active_support/core_ext/name_error"
require "active_support/core_ext/string/starts_ends_with"
require "active_support/dependencies/interlock"
require "active_support/inflector"

module ActiveSupport #:nodoc:
  module Dependencies #:nodoc:
    extend self

    mattr_accessor :interlock, default: Interlock.new

    # :doc:

    # Execute the supplied block without interference from any
    # concurrent loads.
    def self.run_interlock
      Dependencies.interlock.running { yield }
    end

    # Execute the supplied block while holding an exclusive lock,
    # preventing any other thread from being inside a #run_interlock
    # block at the same time.
    def self.load_interlock
      Dependencies.interlock.loading { yield }
    end

    # Execute the supplied block while holding an exclusive lock,
    # preventing any other thread from being inside a #run_interlock
    # block at the same time.
    def self.unload_interlock
      Dependencies.interlock.unloading { yield }
    end

    # :nodoc:

    # Should we turn on Ruby warnings on the first load of dependent files?
    mattr_accessor :warnings_on_first_load, default: false

    # All files ever loaded.
    mattr_accessor :history, default: Set.new

    # All files currently loaded.
    mattr_accessor :loaded, default: Set.new

    # Stack of files being loaded.
    mattr_accessor :loading, default: []

    # 标识 我们该load一个文件还是require一个文件
    # Should we load files or require them?
    mattr_accessor :mechanism, default: ENV["NO_RELOAD"] ? :require : :load

    # The set of directories from which we may automatically load files. Files
    # under these directories will be reloaded on each request in development mode,
    # unless the directory also appears in autoload_once_paths.
    mattr_accessor :autoload_paths, default: []

    # The set of directories from which automatically loaded constants are loaded
    # only once. All directories in this set must also be present in +autoload_paths+.
    mattr_accessor :autoload_once_paths, default: []

    # An array of qualified constant names that have been loaded. Adding a name
    # to this array will cause it to be unloaded the next time Dependencies are
    # cleared.
    mattr_accessor :autoloaded_constants, default: []

    # An array of constant names that need to be unloaded on every request. Used
    # to allow arbitrary constants to be marked for unloading.
    mattr_accessor :explicitly_unloadable_constants, default: []

    # The WatchStack keeps a stack of the modules being watched as files are
    # loaded. If a file in the process of being loaded (parent.rb) triggers the
    # load of another file (child.rb) the stack will ensure that child.rb
    # handles the new constants.
    #
    # If child.rb is being autoloaded, its constants will be added to
    # autoloaded_constants. If it was being required, they will be discarded.
    #
    # This is handled by walking back up the watch stack and adding the constants
    # found by child.rb to the list of original constants in parent.rb.
    class WatchStack
      include Enumerable

      # @watching is a stack of lists of constants being watched. For instance,
      # if parent.rb is autoloaded, the stack will look like [[Object]]. If
      # parent.rb then requires namespace/child.rb, the stack will look like
      # [[Object], [Namespace]].

      def initialize
        @watching = [] # 记录每次监视的模块名称
        @stack = Hash.new { |h, k| h[k] = [] }
      end

      def each(&block)
        @stack.each(&block)
      end

      def watching?
        !@watching.empty?
      end

      # Returns a list of new constants found since the last call to
      # <tt>watch_namespaces</tt>.
      # 返回自从上次调用watch_namespace方法以来发现的常量
      # 返回的是完整常量
      def new_constants
        constants = []

        # Grab the list of namespaces that we're looking for new constants under
        @watching.last.each do |namespace|
          # Retrieve the constants that were present under the namespace when watch_namespaces
          # was originally called
          original_constants = @stack[namespace].last

          # puts "输出original"
          # p original_constants

          if Dependencies.qualified_const_defined?(namespace)
            mod = Inflector.constantize(namespace)
          end

          # 原始源码是有bug的，虽然它基本不会被触发 
          if ! mod.nil? && mod.is_a?(Module)
            # Get a list of the constants that were added
            new_constants = mod.constants(false) - original_constants

            # @stack[namespace] returns an Array of the constants that are being evaluated
            # for that namespace. For instance, if parent.rb requires child.rb, the first
            # element of @stack[Object] will be an Array of the constants that were present
            # before parent.rb was required. The second element will be an Array of the
            # constants that were present before child.rb was required.
            @stack[namespace].each do |namespace_constants|
              # puts "输出namespace_constants"
              # p namespace_constants

              namespace_constants.concat(new_constants)
            end

            # puts "输出new_constants"
            # p new_constants

            # puts "输出@stack"
            # p @stack

            # Normalize the list of new constants, and add them to the list we will return
            new_constants.each do |suffix|
              x_y = [namespace, suffix]
              # puts "输出namespace, suffix"
              # p x_y

              constants << (x_y - ["Object"]).join("::".freeze)
            end
          end # if .. end
          
        end
        constants
      ensure
        # A call to new_constants is always called after a call to watch_namespaces
        # 当执行此方法后，从监视栈中弹出监视的模块与常量
        # 即使发生异常
        #puts "pop之前, #{@watching}"
        pop_modules(@watching.pop)
        #puts "输出@watching, #{@watching}"
      end

      # Add a set of modules to the watch stack, remembering the initial
      # constants.
      # 监视一组模块，@watching保存的是模块的名称,它是一个数组的数组，类似[["String", "Abc"]]
      # 所以只要一直调用这个方法@watching中就一直向内添加模块名称数组
      # @stack是一个hash，分别是模块名称，值为此模块的原始常量数组的数组，类似[[:A, :B]]
      def watch_namespaces(namespaces)
        @watching << namespaces.map do |namespace|
          module_name = Dependencies.to_constant_name(namespace)
          original_constants = Dependencies.qualified_const_defined?(module_name) ?
            Inflector.constantize(module_name).constants(false) : []

          @stack[module_name] << original_constants
          module_name
        end
      end

      private
        # 从监视栈中弹出监视的模块与常量
        def pop_modules(modules)
          modules.each { |mod| @stack[mod].pop }
        end
    end # WatchStack .. end

    # An internal stack used to record which constants are loaded by any block.
    mattr_accessor :constant_watch_stack, default: WatchStack.new

    # Module includes this module.
    module ModuleConstMissing #:nodoc:
      def self.append_features(base)
        base.class_eval do
          # Emulate #exclude via an ivar
          if defined?(@_const_missing) && @_const_missing
            return
          else
            @_const_missing = instance_method(:const_missing)
            remove_method(:const_missing)
          end
        end
        super
      end

      def self.exclude_from(base)
        base.class_eval do
          define_method :const_missing, @_const_missing
          @_const_missing = nil
        end
      end

      def const_missing(const_name)
        # from_mod为Object或当前类(模块)
        from_mod = anonymous? ? guess_for_anonymous(const_name) : self
        #puts "输出from_mod, #{from_mod}, const_name: #{const_name}"
        Dependencies.load_missing_constant(from_mod, const_name)
      end

      # We assume that the name of the module reflects the nesting
      # (unless it can be proven that is not the case) and the path to the file
      # that defines the constant. Anonymous modules cannot follow these
      # conventions and therefore we assume that the user wants to refer to a
      # top-level constant.
      # 检查常量是否定义在Object中，如果是，则抛出异常
      # 证明它不应在匿名模块中
      def guess_for_anonymous(const_name)
        # 这段代码有些莫名其妙，因为如果常量定义于Object或其祖先中(模块或类)，根本不会触发const_missing方法
        # 这算什么？线程安全检查？
        if Object.const_defined?(const_name)
          raise NameError.new "#{const_name} cannot be autoloaded from an anonymous class or module", const_name
        else
          Object
        end
      end

      def unloadable(const_desc = self)
        super(const_desc)
      end
    end

    # Object includes this module.
    module Loadable #:nodoc:
      def self.exclude_from(base)
        base.class_eval do
          define_method(:load, Kernel.instance_method(:load))
          private :load
        end
      end

      def require_or_load(file_name)
        Dependencies.require_or_load(file_name)
      end

      # Interprets a file using <tt>mechanism</tt> and marks its defined
      # constants as autoloaded. <tt>file_name</tt> can be either a string or
      # respond to <tt>to_path</tt>.
      # 使用一种机制解释文件并定义常量自动加载。
      # file_name可以可以是字符串或是响应to_path方法的对象
      #
      # Use this method in code that absolutely needs a certain constant to be
      # defined at that point. A typical use case is to make constant name
      # resolution deterministic for constants with the same relative name in
      # different namespaces whose evaluation would depend on load order
      # otherwise.
      def require_dependency(file_name, message = "No such file to load -- %s.rb")
        if file_name.respond_to?(:to_path)
          file_name = file_name.to_path
        end

        if ! file_name.is_a?(String)
          raise ArgumentError, "the file name must either be a String or implement #to_path -- you passed #{file_name.inspect}"
        end

        Dependencies.depend_on(file_name, message)
      end

      # 如果是load模式，且当前正在监视文件的化，调用new_constants_in方法
      # 否则执行yield块，它一般的实现是Kernel#load一个文件
      # 不应依赖它的返回值
      def load_dependency(file)
        if Dependencies.load? && Dependencies.constant_watch_stack.watching?
          Dependencies.new_constants_in(Object) { yield }
        else
          yield
        end
      rescue Exception => exception  # errors from loading file
        exception.blame_file! file if exception.respond_to? :blame_file!
        raise
      end

      # Mark the given constant as unloadable. Unloadable constants are removed
      # each time dependencies are cleared.
      #
      # Note that marking a constant for unloading need only be done once. Setup
      # or init scripts may list each unloadable constant that may need unloading;
      # each constant will be removed for every subsequent clear, as opposed to
      # for the first clear.
      #
      # The provided constant descriptor may be a (non-anonymous) module or class,
      # or a qualified constant name as a string or symbol.
      #
      # Returns +true+ if the constant was not previously marked for unloading,
      # +false+ otherwise.
      def unloadable(const_desc)
        Dependencies.mark_for_unload const_desc
      end

      private
        # 重写了系统的load, require
        # 都采用load_dependency方法实现
        def load(file, wrap = false)
          result = false
          load_dependency(file) { result = super }
          result
        end

        def require(file)
          result = false
          load_dependency(file) { result = super }
          result
        end
    end # Loadable .. end

    # Exception file-blaming.
    # 
    # 这个模块扩展了exception，
    # 它可以描述是加载哪个文件发生的错误
    module Blamable #:nodoc:
      def blame_file!(file)
        (@blamed_files ||= []).unshift file
      end

      def blamed_files
        @blamed_files ||= []
      end

      def describe_blame
        return nil if blamed_files.empty?
        "This error occurred while loading the following files:\n   #{blamed_files.join "\n   "}"
      end

      def copy_blame!(exc)
        @blamed_files = exc.blamed_files.clone
        self
      end
    end

    def hook!
      Object.class_eval { include Loadable }
      # 由于Module继承自Object, 那么Module也包含了Loadable模块的方法
      Module.class_eval { include ModuleConstMissing } 
      Exception.class_eval { include Blamable }
    end

    def unhook!
      ModuleConstMissing.exclude_from(Module)
      Loadable.exclude_from(Object)
    end

    def load?
      mechanism == :load
    end

    def depend_on(file_name, message = "No such file to load -- %s.rb")
      path = search_for_file(file_name) # 判断是否在autoload_paths中
      require_or_load(path || file_name)
    rescue LoadError => load_error
      if file_name = load_error.message[/ -- (.*?)(\.rb)?$/, 1]
        load_error.message.replace(message % file_name)
        load_error.copy_blame!(load_error)
      end
      raise
    end

    def clear
      Dependencies.unload_interlock do
        loaded.clear
        loading.clear
        remove_unloadable_constants!
      end
    end

    def require_or_load(file_name, const_path = nil)
      if file_name =~ /\.rb\z/
        file_name = $`
      end
      #puts "输出file_name: #{file_name}， const_path: #{const_path}"

      expanded = File.expand_path(file_name)
      return if loaded.include?(expanded)

      Dependencies.load_interlock do
        # Maybe it got loaded while we were waiting for our lock:
        # 也许等待锁的时候已经被加载了
        return if loaded.include?(expanded)

        # Record that we've seen this file *before* loading it to avoid an
        # infinite loop with mutual dependencies.
        loaded << expanded
        loading << expanded

        begin
          if load?
            # Enable warnings if this file has not been loaded before and
            # warnings_on_first_load is set.
            load_args = ["#{file_name}.rb"]
            if ! const_path.nil?
              load_args << const_path
            end

            # puts "输出*load_args, #{load_args}"
            # p *load_args

            # 这里load_args是一个数组，*load_args将作为参数依次传入

            if !warnings_on_first_load || history.include?(expanded)
              result = load_file(*load_args)
            else
              enable_warnings { result = load_file(*load_args) }
            end
          else
            result = require file_name
          end
        rescue Exception
          loaded.delete expanded
          raise
        ensure
          loading.pop
        end

        # Record history *after* loading so first load gets warnings.
        history << expanded
        result
      end
    end # require_or_load .. end

    # Is the provided constant path defined?
    def qualified_const_defined?(path)
      Object.const_defined?(path, false)
    end

    # Given +path+, a filesystem path to a ruby file, return an array of
    # constant paths which would cause Dependencies to attempt to load this
    # file.
    # 如果path是autoload_paths目录下的目录或文件
    # 返回paths(数组), 当一个目录和子目录都被添加到autoload_paths中时，
    # 会被返回多个路径
    def loadable_constants_for_path(path, bases = autoload_paths)
      if path =~ /\.rb\z/
        path = $`
      end
      expanded_path = File.expand_path(path)

      paths = []
      bases.each do |root|
        expanded_root = File.expand_path(root)
        if expanded_path.start_with?(expanded_root)

          root_size = expanded_root.size
          if expanded_path[root_size] == "/".freeze
            
            nesting = expanded_path[(root_size + 1)..-1]
            if ! nesting.blank?
              paths << nesting.camelize # 如果有嵌套关系，以::分隔
            end
          end

        end # if expanded_path .. end

      end # bases .. end

      paths.uniq!
      #puts "输出paths: #{paths}"
      paths
    end

    # Search for a file in autoload_paths matching the provided suffix.
    # 在autoload_paths路径中搜索文件，例如：
    # 一个auto_paths中有这么一个目录: app/xt/, path_suffix 为hello
    # 那么检测它是否存在？
    # 这个方法是用于检测文件, 而不是目录
    # 如果存在，返回完整路径，否则返回nil
    def search_for_file(path_suffix)
      path_suffix = path_suffix.sub(/(\.rb)?$/, ".rb".freeze)

      autoload_paths.each do |root|
        path = File.join(root, path_suffix)

        if File.file? path
          return path
        end
        
      end
      nil # Gee, I sure wish we had first_match ;-)
    end

    # Does the provided path_suffix correspond to an autoloadable module?
    # Instead of returning a boolean, the autoload base for this module is
    # returned.
    # 在autoload_paths的路径测试，组成的路径是否是一个目录
    # 例如有一个autoload_path路径为，app/xt
    def autoloadable_module?(path_suffix)
      _load_path = nil
      autoload_paths.each do |load_path|
        
        if File.directory? File.join(load_path, path_suffix)
          _load_path = load_path
          break
        end

      end
      
      return _load_path
    end

    def load_once_path?(path)
      # to_s works around a ruby issue where String#starts_with?(Pathname)
      # will raise a TypeError: no implicit conversion of Pathname into String
      autoload_once_paths.any? { |base| path.starts_with? base.to_s }
    end

    # Attempt to autoload the provided module name by searching for a directory
    # matching the expected path suffix. If found, the module is created and
    # assigned to +into+'s constants with the name +const_name+. Provided that
    # the directory was loaded from a reloadable base path, it is added to the
    # set of constants that are to be unloaded.
    # 只是判断是否包含一个目录，返回一个Module，如果在此模块中包含方法
    # 此时，是无法访问到方法的。
    # 例如 自动加载路径为xt/，下面有/model2/xx.rb, xx.rb中定义着Xx类，它
    # 的上层模块是Model2, 只有在加载了Xx类之后，才能方法Model2模块定义的
    # 方法
    def autoload_module!(into, const_name, qualified_name, path_suffix)
      mod = nil

      base_path = autoloadable_module?(path_suffix)
      if base_path
        mod = Module.new
        into.const_set const_name, mod
        autoloaded_constants << qualified_name unless autoload_once_paths.include?(base_path)
        autoloaded_constants.uniq!
      end
      
      return mod
    end

    # Load the file at the provided path. +const_paths+ is a set of qualified
    # constant names. When loading the file, Dependencies will watch for the
    # addition of these constants. Each that is defined will be marked as
    # autoloaded, and will be removed when Dependencies.clear is next called.
    #
    # If the second parameter is left off, then Dependencies will construct a
    # set of names that the file at +path+ may define. See
    # +loadable_constants_for_path+ for more details.
    # 
    # 加载一个文件，并将新增的常量添加到autoloaded_constants中
    def load_file(path, const_paths = loadable_constants_for_path(path))
      #puts "const_paths: #{const_paths}"

      # 转为非空数组
      if ! const_paths.is_a? Array
        const_paths = [const_paths].compact
      end
      parent_paths = const_paths.collect { |const_path| const_path[/.*(?=::)/] || ::Object }

      result = nil
      newly_defined_paths = new_constants_in(*parent_paths) do
        result = Kernel.load path
      end

      # puts "输出newly"
      # p newly_defined_paths

      if ! load_once_path?(path)
        autoloaded_constants.concat newly_defined_paths
      end
      autoloaded_constants.uniq!
      
      return result
    end

    # Returns the constant path for the provided parent and constant name.
    # 返回以::分隔的常量字符串，例如Model2::Abc
    def qualified_name_for(mod, name)
      mod_name = to_constant_name mod
      mod_name == "Object" ? name.to_s : "#{mod_name}::#{name}"
    end

    # Load the constant named +const_name+ which is missing from +from_mod+. If
    # it is not possible to load the constant into from_mod, try its parent
    # module using +const_missing+.
    # 加载常量，优先从文件中加载，然后尝试加载目录，最后从父模块中尝试加载
    # 它是根据::分隔符，逐级加载的
    # 
    def load_missing_constant(from_mod, const_name)
      unless qualified_const_defined?(from_mod.name) && Inflector.constantize(from_mod.name).equal?(from_mod)
        raise ArgumentError, "A copy of #{from_mod} has been removed from the module tree but is still active!"
      end

      qualified_name = qualified_name_for from_mod, const_name
      path_suffix = qualified_name.underscore # 常量保存的路径,根据约定

      file_path = search_for_file(path_suffix)

      #puts "load_missing_constant: #{from_mod}, #{const_name}"

      if file_path
        expanded = File.expand_path(file_path)
        expanded.sub!(/\.rb\z/, "".freeze)

        if loading.include?(expanded)
          raise "Circular dependency detected while autoloading constant #{qualified_name}"
        else
          require_or_load(expanded, qualified_name)
          if ! from_mod.const_defined?(const_name, false)
            raise LoadError, "Unable to autoload constant #{qualified_name}, expected #{file_path} to define it"
          end

          return from_mod.const_get(const_name)
        end
      elsif mod = autoload_module!(from_mod, const_name, qualified_name, path_suffix)
        return mod
      else
        # 这个分支其实在模仿ruby const_missing的行为，对于完全限定名形式访问常量，
        # ruby不会去加载父模块的常量，这里如果没有找到常量，调用其父模块的常量
        # 否则触发NameError异常，这是模仿ruby的默认行为
        # 
        # 如果from_mod == parent_mod, 即from_mod是Object和父类没有定义常量时，
        # 调用父类的const_missing，否则抛出NameError异常

        parent = from_mod.parent
        # 是否定义在父模块中
        any_r = from_mod.parents.any? { |p| p.const_defined?(const_name, false) }

        # 当from_mod为Object时，parent == from_mod
        if parent != from_mod && ! any_r
          # If our parents do not have a constant named +const_name+ then we are free
          # to attempt to load upwards. If they do have such a constant, then this
          # const_missing must be due to from_mod::const_name, which should not
          # return constants from from_mod's parents.
          begin
            # Since Ruby does not pass the nesting at the point the unknown
            # constant triggered the callback we cannot fully emulate constant
            # name lookup and need to make a trade-off: we are going to assume
            # that the nesting in the body of Foo::Bar is [Foo::Bar, Foo] even
            # though it might not be. Counterexamples are
            #
            #   class Foo::Bar
            #     Module.nesting # => [Foo::Bar]
            #   end
            #
            # or
            #
            #   module M::N
            #     module S::T
            #       Module.nesting # => [S::T, M::N]
            #     end
            #   end
            #
            # for example.
            return parent.const_missing(const_name)
          rescue NameError => e
            if e.missing_name? qualified_name_for(parent, const_name)
              raise
            end

          end
        else
          name_error = NameError.new("uninitialized constant #{qualified_name}", const_name)
          name_error.set_backtrace(caller.reject { |l| l.starts_with? __FILE__ })
          raise name_error
        end # inner if .. else .. end
      end # if .. end

      
    end # load_missing_constant .. end

    # Remove the constants that have been autoloaded, and those that have been
    # marked for unloading. Before each constant is removed a callback is sent
    # to its class/module if it implements +before_remove_const+.
    #
    # The callback implementation should be restricted to cleaning up caches, etc.
    # as the environment will be in an inconsistent state, e.g. other constants
    # may have already been unloaded and not accessible.
    def remove_unloadable_constants!
      autoloaded_constants.each { |const| remove_constant const }
      autoloaded_constants.clear
      Reference.clear!
      explicitly_unloadable_constants.each { |const| remove_constant const }
    end

    class ClassCache
      def initialize
        @store = Concurrent::Map.new
      end

      def empty?
        @store.empty?
      end

      def key?(key)
        @store.key?(key)
      end

      def get(key)
        key = key.name if key.respond_to?(:name)
        @store[key] ||= Inflector.constantize(key)
      end
      alias :[] :get

      def safe_get(key)
        key = key.name if key.respond_to?(:name)
        @store[key] ||= Inflector.safe_constantize(key)
      end

      def store(klass)
        return self unless klass.respond_to?(:name)
        raise(ArgumentError, "anonymous classes cannot be cached") if klass.name.empty?
        @store[klass.name] = klass
        self
      end

      def clear!
        @store.clear
      end
    end

    Reference = ClassCache.new

    # Store a reference to a class +klass+.
    def reference(klass)
      Reference.store klass
    end

    # Get the reference for class named +name+.
    # Raises an exception if referenced class does not exist.
    def constantize(name)
      Reference.get(name)
    end

    # Get the reference for class named +name+ if one exists.
    # Otherwise returns +nil+.
    def safe_constantize(name)
      Reference.safe_get(name)
    end

    # Determine if the given constant has been automatically loaded.
    def autoloaded?(desc)
      return false if desc.is_a?(Module) && desc.anonymous?
      name = to_constant_name desc
      return false unless qualified_const_defined?(name)
      autoloaded_constants.include?(name)
    end

    # Will the provided constant descriptor be unloaded?
    def will_unload?(const_desc)
      autoloaded?(const_desc) ||
        explicitly_unloadable_constants.include?(to_constant_name(const_desc))
    end

    # Mark the provided constant name for unloading. This constant will be
    # unloaded on each request, not just the next one.
    def mark_for_unload(const_desc)
      name = to_constant_name const_desc
      if explicitly_unloadable_constants.include? name
        false
      else
        explicitly_unloadable_constants << name
        true
      end
    end

    # Run the provided block and detect the new constants that were loaded during
    # its execution. Constants may only be regarded as 'new' once -- so if the
    # block calls +new_constants_in+ again, then the constants defined within the
    # inner call will not be reported in this one.
    #
    # If the provided block does not run to completion, and instead raises an
    # exception, any new constants are regarded as being only partially defined
    # and will be removed immediately.
    # 
    # 这个方法正确的实现是，监视父模块，通过提供一个块，
    def new_constants_in(*descs)
      # puts "输出descs"
      # p descs
      constant_watch_stack.watch_namespaces(descs)
      success = false

      begin
        #puts "输出constant_watch_stack, #{constant_watch_stack}"
        yield # Now yield to the code that is to define new constants.
        success = true
      ensure
        new_constants = constant_watch_stack.new_constants

        #puts "success: #{success}, new_constants:#{new_constants}"

        if success
          return new_constants
        else
          # Remove partially loaded constants.
          new_constants.each { |c| remove_constant(c) }
        end
    
      end
    end

    # Convert the provided const desc to a qualified constant name (as a string).
    # A module, class, symbol, or string may be provided.
    # 将常量名称转换为字符串
    def to_constant_name(desc) #:nodoc:
      case desc
      when String then desc.sub(/^::/, "")
      when Symbol then desc.to_s
      when Module
        desc.name ||
          raise(ArgumentError, "Anonymous modules have no name to be referenced by")
      else raise TypeError, "Not a valid constant descriptor: #{desc.inspect}"
      end
    end

    # 移除常量
    def remove_constant(const) #:nodoc:
      # Normalize ::Foo, ::Object::Foo, Object::Foo, Object::Object::Foo, etc. as Foo.
      normalized = const.to_s.sub(/\A::/, "")
      normalized.sub!(/\A(Object::)+/, "")

      constants = normalized.split("::")
      to_remove = constants.pop

      # Remove the file path from the loaded list.
      file_path = search_for_file(const.underscore)
      if file_path
        expanded = File.expand_path(file_path)
        expanded.sub!(/\.rb\z/, "")
        loaded.delete(expanded)
      end

      if constants.empty?
        parent = Object
      else
        # This method is robust to non-reachable constants.
        #
        # Non-reachable constants may be passed if some of the parents were
        # autoloaded and already removed. It is easier to do a sanity check
        # here than require the caller to be clever. We check the parent
        # rather than the very const argument because we do not want to
        # trigger Kernel#autoloads, see the comment below.
        parent_name = constants.join("::")
        if ! qualified_const_defined?(parent_name)
          return
        end
        
        parent = constantize(parent_name)
      end

      # In an autoloaded user.rb like this
      #
      #   autoload :Foo, 'foo'
      #
      #   class User < ActiveRecord::Base
      #   end
      #
      # we correctly register "Foo" as being autoloaded. But if the app does
      # not use the "Foo" constant we need to be careful not to trigger
      # loading "foo.rb" ourselves. While #const_defined? and #const_get? do
      # require the file, #autoload? and #remove_const don't.
      #
      # We are going to remove the constant nonetheless ---which exists as
      # far as Ruby is concerned--- because if the user removes the macro
      # call from a class or module that were not autoloaded, as in the
      # example above with Object, accessing to that constant must err.
      # const_get方法会触发autoload，导致常量被定义到了Object中，
      # 这段代码处理不是autoload的常量的回调
      if ! parent.autoload?(to_remove)
        begin
          constantized = parent.const_get(to_remove, false)
        rescue NameError
          # The constant is no longer reachable, just skip it.
          return
        else # 没有发生异常的情况
          constantized.before_remove_const if constantized.respond_to?(:before_remove_const)
        end
      end # if ! parent.autoload? .. end

      begin
        parent.instance_eval { remove_const to_remove }
      rescue NameError
        # The constant is no longer reachable, just skip it.
      end
    end # remove_constant .. end

  end
end

ActiveSupport::Dependencies.hook!
