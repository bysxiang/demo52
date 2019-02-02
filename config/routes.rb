Rails.application.routes.draw do
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html

  root "welcome#index"



  require "sidekiq/web"
  Sidekiq::Web.use Rack::Auth::Basic do |username, password|
    username == "ybs_songshipeng" && password == "ybs4009900365"
  end
  mount Sidekiq::Web, at: "/sidekiq"

  get "/index2" => "welcome#index2"

  get "/index3" => "welcome#index3"
end
