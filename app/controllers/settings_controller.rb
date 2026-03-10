class SettingsController < ApplicationController
  def edit
    @vessel = current_vessel
    @vessel.build_relay_account unless @vessel.relay_account
  end

  def update
    @vessel = current_vessel

    if @vessel.update(settings_params)
      redirect_to edit_settings_path, notice: "Settings saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def settings_params
      params.require(:vessel).permit(
        :callsign, :sailmail_address,
        :bundle_ratio, :daily_budget_kb,
        relay_account_attributes: %i[
          imap_server imap_port imap_username imap_password imap_use_ssl
          smtp_server smtp_port smtp_username smtp_password smtp_use_starttls
        ],
      )
    end
end
