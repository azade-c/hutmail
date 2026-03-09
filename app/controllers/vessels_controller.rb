class VesselsController < ApplicationController
  def new
    @vessel = Vessel.new
  end

  def create
    @vessel = Vessel.new(vessel_params)
    @vessel.captain = current_user

    if @vessel.save
      redirect_to dashboard_path, notice: "Vessel created — welcome aboard! ⛵"
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
    def vessel_params
      params.expect(vessel: %i[ name callsign sailmail_address ])
    end
end
