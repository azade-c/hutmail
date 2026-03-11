class BundlePreviewsController < ApplicationController
  include VesselScoped

  def show
    @preview = @vessel.preview_bundle
  end
end
