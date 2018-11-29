module ThreadTest
  class Abc
    extend ActiveSupport::PerThreadRegistry

    def show
      puts "Abc#show"
    end

    def self.show2
      instance.show

      p Thread.current.keys

      puts "#{@per_thread_registry_key.class}, #{Thread.current['Abc']}"
      
      puts "Abc.show 类方法"
    end
  end
end

ThreadTest::Abc.show