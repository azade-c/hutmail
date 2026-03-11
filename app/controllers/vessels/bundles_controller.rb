class Vessels::BundlesController < ApplicationController
  include VesselScoped

  def index
    @bundles = @vessel.bundles.recent.limit(20)
  end
end
