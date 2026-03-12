class Vessels::DispatchesController < ApplicationController
  include VesselScoped

  def create
    @vessel.collect_all_accounts
    @bundle = @vessel.dispatch_now

    if @bundle
      redirect_to bundle_path(@bundle), notice: "Dépêche envoyée (#{@bundle.messages_count} messages)"
    else
      redirect_to vessel_path(@vessel), notice: "Aucun message à dépêcher"
    end
  end
end
