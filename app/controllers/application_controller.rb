class ApplicationController < ActionController::Base
  include Authentication

  allow_browser versions: :modern
  stale_when_importmap_changes

  private
    def current_user
      Current.user
    end
    helper_method :current_user
end
