class VesselsController < ApplicationController
  def new
    @vessel = Vessel.new
  end

  def create
    @vessel = Vessel.setup(vessel_params, captain: current_user)
    redirect_to dashboard_path, notice: "Vessel created — welcome aboard! ⛵"
  rescue ActiveRecord::RecordInvalid => e
    @vessel = e.record
    render :new, status: :unprocessable_entity
  end

  private
    def vessel_params
      params.expect(vessel: %i[ name callsign sailmail_address ])
    end
end
