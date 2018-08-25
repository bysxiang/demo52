class Test2
  include Sidekiq::Worker

  sidekiq_options :queue => "test_queue"

  def perform(*args)
    puts "执行test2 worker, #{args}"
  end
end