class BundlesController < ApplicationController
  include BundleScoped

  def show
    @messages = @bundle.message_digests.includes(:mail_account).ordered
  end
end
