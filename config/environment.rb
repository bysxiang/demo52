# Load the Rails application.
require_relative 'application'

require 'sidekiq/fetch'


# Initialize the Rails application.
Rails.application.initialize!

Sidekiq.configure_client do |config|
  config.client_middleware do |chain|
    #chain.add Queue2::Hello
    #chain.add Queue2::Hello2
  end
end


#Test.perform_in(3500, 33)
#Test2.perform_async(44)

# fetch = Sidekiq::BasicFetch.new(:queues => ["default"])
# uow = fetch.retrieve_work

# p uow
