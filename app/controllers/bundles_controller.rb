class BundlesController < ApplicationController
  def index
    @bundles = current_vessel.bundles.recent.limit(20)
  end

  def show
    @bundle = current_vessel.bundles.find(params[:id])
    @messages = @bundle.collected_messages.includes(:mail_account)
  end
end
