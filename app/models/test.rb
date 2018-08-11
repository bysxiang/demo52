class Test
  include Sidekiq::Worker

  def perform(*args)
    puts "执行test worker"
  end
end