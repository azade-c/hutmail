class HomeController < ApplicationController
  allow_unauthenticated_access


  def show
    redirect_to vessels_path if authenticated?
  end
end
