class Vessels::DispatchesController < ApplicationController
  include VesselScoped

  def create
    @vessel.collect_all_accounts
    @bundle = @vessel.dispatch_now

    if @bundle
      redirect_to bundle_path(@bundle), notice: status_notice(@bundle)
    else
      redirect_to vessel_path(@vessel), notice: "Aucun message à dépêcher"
    end
  end

  private
    def status_notice(bundle)
      if bundle.sent?
        "Dépêche envoyée (#{bundle.messages_count} messages)"
      else
        "Erreur lors de l'envoi — voir le journal ci-dessous"
      end
    end
end
