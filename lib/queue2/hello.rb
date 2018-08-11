module Queue2
  class Hello
    def initialize()
      
    end

    # 中间件必须返回一个值
    # 默认的yield会返回提供的块的返回值
    def call(*args)
      puts "进入Hello, #{args}"
      puts "参数长度: #{args.length}"
      r = yield
      puts "hello 结束"

      r
    end
  end
end