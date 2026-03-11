class BundlesController < ApplicationController
  include BundleScoped

  def show
    @messages = @bundle.collected_messages.includes(:mail_account).ordered
  end
end
