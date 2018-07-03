class WelcomeController < ApplicationController

  def index
    session[:ixx] = {789 => 323434 }
    puts "我是index222"
    p session[:ixx]
  end

  def index2
    xx = session[:ixx]

    byebug

    puts "xx等于：#{xx}"

    render plain: "xxx"
  end
end