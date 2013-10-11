class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :exception

  helper_method :current_user

  private

  # return current_user, using existing object if available to save db hits
  def current_user
    @current_user ||= User.find(session[:user_id]) if session[:user_id]
  end

  def require_login
    unless current_user
      session[:login_redirect_url] = request.original_url
      redirect_to log_in_url, notice: "Please log in to perform this action."
    end
  end
end
