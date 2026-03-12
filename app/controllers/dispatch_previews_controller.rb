class DispatchPreviewsController < ApplicationController
  include VesselScoped

  def show
    @vessel.collect_all_accounts
    @preview = @vessel.preview_dispatch
  end
end
