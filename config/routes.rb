Rails.application.routes.draw do
  # devise_for :employees, controllers: {
  #   sessions: "employees/sessions"
  # }

  devise_for :employees,
   :path => "auth",
   :controllers =>  {sessions: "employees/sessions"}
   # ,
   # :path_names => 
   # {
   #    :sign_in => 'login',
   #    :sign_out => 'logout',
   #    :password => 'secret',
   #    :confirmation => 'verification',
   #    :unlock => 'unblock',
   #    :registration => 'register',
   #    :sign_up => 'cmon_let_me_in'
   #  }


  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html

  
  get "main/index"
  get "main/test_json"

  root "welcome#index"               





  require "sidekiq/web"
  Sidekiq::Web.use Rack::Auth::Basic do |username, password|
    username == "ybs_songshipeng" && password == "ybs4009900365"
  end
  mount Sidekiq::Web, at: "/sidekiq"

  get "/index2" => "welcome#index2"

  get "/index3" => "welcome#index3"
end
