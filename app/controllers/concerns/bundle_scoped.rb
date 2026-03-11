module BundleScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_bundle, :set_vessel
    helper_method :current_vessel
  end

  private
    def set_bundle
      @bundle = Bundle.find(params[:id])
    end

    def set_vessel
      @vessel = current_user.vessels.find_by(id: @bundle.vessel_id)

      unless @vessel
        redirect_to vessels_path, alert: "Bateau introuvable"
      end
    end

    def current_vessel = @vessel
end
