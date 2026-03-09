class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  def current_user
    Current.user
  end
  helper_method :current_user

  def current_vessel
    @current_vessel ||= current_user&.primary_vessel
  end
  helper_method :current_vessel
end
