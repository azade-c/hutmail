class TracksController < ApplicationController
  allow_unauthenticated_access

  layout "track"

  def show
    @vessel = Vessel.find_by!(track_slug: params[:slug])
    @reports = @vessel.position_reports.chronological.to_a
    @distance_nm = PositionReport.total_distance_nm(@reports)

    # A live boat position is not something to leave in a search index.
    response.set_header("X-Robots-Tag", "noindex, nofollow")

    respond_to do |format|
      format.html
      format.kml { render layout: false, content_type: Mime[:kml].to_s }
    end
  end
end
