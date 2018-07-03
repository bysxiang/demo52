# frozen_string_literal: true

require "active_support/core_ext/time/calculations"

module ActiveSupport
  # FileUpdateChecker specifies the API used by Rails to watch files
  # and control reloading. The API depends on four methods:
  #
  # * +initialize+ which expects two parameters and one block as
  #   described below.
  #
  # * +updated?+ which returns a boolean if there were updates in
  #   the filesystem or not.
  #
  # * +execute+ which executes the given block on initialization
  #   and updates the latest watched files and timestamp.
  #
  # * +execute_if_updated+ which just executes the block if it was updated.
  #
  # After initialization, a call to +execute_if_updated+ must execute
  # the block only if there was really a change in the filesystem.
  #
  # This class is used by Rails to reload the I18n framework whenever
  # they are changed upon a new request.
  #
  #   i18n_reloader = ActiveSupport::FileUpdateChecker.new(paths) do
  #     I18n.reload!
  #   end
  #
  #   ActiveSupport::Reloader.to_prepare do
  #     i18n_reloader.execute_if_updated
  #   end
  class FileUpdateChecker
    # It accepts two parameters on initialization. The first is an array
    # of files and the second is an optional hash of directories. The hash must
    # have directories as keys and the value is an array of extensions to be
    # watched under that directory.
    #
    # This method must also receive a block that will be called once a path
    # changes. The array of files and list of directories cannot be changed
    # after FileUpdateChecker has been initialized.
    # 
    # files表示的是文件列表
    # dirs是一个hash，键为目录名称，值为要纳入监视的文件扩展名数组 => { "app" => ["rb", "txt"] }
    def initialize(files, dirs = {}, &block)
      unless block
        raise ArgumentError, "A block is required to initialize a FileUpdateChecker"
      end

      @files = files.freeze
      @glob  = compile_glob(dirs)
      @block = block

      @watched    = nil
      @updated_at = nil

      @last_watched   = watched
      @last_update_at = updated_at(@last_watched)
    end

    # Check if any of the entries were updated. If so, the watched and/or
    # updated_at values are cached until the block is executed via +execute+
    # or +execute_if_updated+.
    #
    # 检查是否被更新了，如果更新了的化，会修改@watched与updated_at
    def updated?
      current_watched = watched
      if @last_watched.size != current_watched.size
        @watched = current_watched
        true
      else
        current_updated_at = updated_at(current_watched)
        if @last_update_at < current_updated_at
          @watched    = current_watched
          @updated_at = current_updated_at
          true
        else
          false
        end
      end
    end

    # Executes the given block and updates the latest watched files and
    # timestamp.
    # 
    # 执行给定的块，并更新@watched和@last_update_at
    def execute
      @last_watched   = watched
      @last_update_at = updated_at(@last_watched)
      @block.call
    ensure
      @watched = nil
      @updated_at = nil
    end

    # Execute the block given if updated.
    # 
    # 如果监控的文件被更新，执行指定的块
    def execute_if_updated
      if updated?
        yield if block_given?
        execute
        true
      else
        false
      end
    end

    private

      # 返回要监视的所有文件列表
      def watched
        @watched || begin
          all = @files.select { |f| File.exist?(f) }
          if @glob
            all.concat(Dir[@glob])
          end
          
          all
        end
      end

      # 最后修改时间
      def updated_at(paths)
        @updated_at || max_mtime(paths) || Time.at(0)
      end

      # This method returns the maximum mtime of the files in +paths+, or +nil+
      # if the array is empty.
      #
      # Files with a mtime in the future are ignored. Such abnormal situation
      # can happen for example if the user changes the clock by hand. It is
      # healthy to consider this edge case because with mtimes in the future
      # reloading is not triggered.
      #
      # 获取最大的修改时间
      def max_mtime(paths)
        time_now = Time.now
        max_mtime = nil

        # Time comparisons are performed with #compare_without_coercion because
        # AS redefines these operators in a way that is much slower and does not
        # bring any benefit in this particular code.
        #
        # Read t1.compare_without_coercion(t2) < 0 as t1 < t2.
        paths.each do |path|
          mtime = File.mtime(path)

          if time_now.compare_without_coercion(mtime) >= 0
            if max_mtime.nil? || max_mtime.compare_without_coercion(mtime) < 0
              max_mtime = mtime
            end
          end
        end

        return max_mtime
      end

      # 根据构造函数的dirs，生成glob规则
      # dirs指定了不同目录检索的文件类型
      def compile_glob(hash)
        hash.freeze # Freeze so changes aren't accidentally pushed
        if ! hash.empty?
          globs = hash.map do |key, value|
            "#{escape(key)}/**/*#{compile_ext(value)}"
          end

          return "{#{globs.join(",")}}"
        else
          return
        end
      end

      def escape(key)
        key.gsub(",", '\,')
      end

      # 生成.{txt,rb}这样的规则
      # 用于Dir.glob
      def compile_ext(array)
        array = Array(array)

        if ! array.empty?
          return ".{#{array.join(",")}}"
        else
          return
        end
        
      end # compile_ext .. end

  end
end
