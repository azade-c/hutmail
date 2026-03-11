class DispatchPreviewsController < ApplicationController
  include VesselScoped

  def show
    @preview = @vessel.preview_dispatch
  end
end
