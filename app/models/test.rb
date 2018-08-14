class Test
  include Sidekiq::Worker

  def perform(*args)
    puts "执行test worker, 将要暂停20s"
    sleep 15
    puts "从暂停中恢复，现在结束"
  end
end