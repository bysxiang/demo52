require_relative 'boot'

require 'rails/all'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Demo52
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 5.2

    puts "加载5.2"

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration can go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded after loading
    # the framework and any gems in your application.

    #config.eager_load_paths += Dir["#{Rails.root}/app"]
    #config.paths.add File.join("app", "xt"), glob: "*.rb", eager_load: true
    config.paths.add File.join("app"), eager_load: true

    config.autoload_paths += ["#{Rails.root}/lib"]
    config.autoload_paths += ["#{Rails.root}/lib/test2"]

    Rails.application.config.session_store :cache_store, key: 'demo_52_session'
  end
end
