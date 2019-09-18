# frozen_string_literal: true

class Employees::SessionsController < Devise::SessionsController
  # before_action :configure_sign_in_params, only: [:create]
  before_action :check_kind, only: [:create]

  # GET /resource/sign_in
  def new
    puts "进入new"
    super
  end

  # POST /resource/sign_in
  def create
    puts "进入create"
    super do |resource|

      resource.current_xx = "java"
      result = bypass_sign_in(resource)
      puts "bypass result: #{result}"
      
    end
  end

  # DELETE /resource/sign_out
  def destroy
    super
  end

  protected

    def check_kind
      kind = resource_params[:kind].to_i

      if kind != 0
        puts "check_kind 要跳转了"
        flash[:alert] = "当前用户，无此角色"
        redirect_to new_employee_session_url
      end      
    end

  # If you have extra params to permit, append them to the sanitizer.
  # def configure_sign_in_params
  #   devise_parameter_sanitizer.permit(:sign_in, keys: [:attribute])
  # end
end
