module Queue2
  class Hello2
    def initialize()
      
    end

    def call(*args)
      puts "进入Hello2, #{args}"
      puts "参数长度: #{args.length}"
      yield
      puts "hello2 结束"
    end
  end
end