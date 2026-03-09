class VesselsController < ApplicationController
  def new
    redirect_to dashboard_path if current_vessel
    @vessel = Vessel.new
  end

  def create
    redirect_to dashboard_path and return if current_vessel

    @vessel = Vessel.new(vessel_params)
    if @vessel.save
      Crew.create!(user: current_user, vessel: @vessel, role: "captain")
      redirect_to dashboard_path, notice: "Vessel created — welcome aboard! ⛵"
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def vessel_params
    params.require(:vessel).permit(:name, :callsign, :sailmail_address)
  end
end
