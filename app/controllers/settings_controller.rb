class SettingsController < ApplicationController
  include VesselScoped

  def edit
    @vessel.build_relay_account unless @vessel.relay_account
  end

  def update
    if @vessel.update(settings_params)
      redirect_to edit_vessel_settings_path(@vessel), notice: "Réglages enregistrés."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def settings_params
      params.require(:vessel).permit(
        :name, :sailmail_address,
        :bundle_ratio, :daily_budget_kb,
        relay_account_attributes: %i[
          imap_server imap_port imap_username imap_password imap_encryption
          smtp_server smtp_port smtp_username smtp_password smtp_encryption
        ],
      )
    end
end
