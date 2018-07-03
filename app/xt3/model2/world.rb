module Model2
  class World
    def self.show
      puts "我是World.show"
    end
  end

  def self.show
    puts "我是self.show"
  end

  def show2()
    puts "我是show2"
  end
end