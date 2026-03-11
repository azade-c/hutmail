class BundlesController < ApplicationController
  include VesselScoped

  def index
    @bundles = @vessel.bundles.recent.limit(20)
  end

  def show
    @bundle = @vessel.bundles.find(params[:id])
    @messages = @bundle.collected_messages.includes(:mail_account).oldest_first
  end
end
