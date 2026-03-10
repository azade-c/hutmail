class VesselsController < ApplicationController
  def new
    @vessel = Vessel.new
    @vessel.build_relay_account
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
      params.require(:vessel).permit(
        :name, :callsign, :sailmail_address,
        relay_account_attributes: %i[
          imap_server imap_port imap_username imap_password imap_use_ssl
          smtp_server smtp_port smtp_username smtp_password smtp_use_starttls
        ],
      )
    end
end
