class MainController < ApplicationController
  before_action :authenticate_employee!

  def index
    puts "输出current_xx, #{session['warden.user.employee.key']}"


    render plain: "java"
  end

  def test_json

    render json: { name: "java", age: 13 }
  end
end