class HomeController < ApplicationController
  allow_unauthenticated_access


  def show
    redirect_to dashboard_path if authenticated?
  end
end
