class SettingsController < ApplicationController
  def edit
    @user = current_user
  end

  def update
    @user = current_user

    if @user.update(settings_params)
      redirect_to edit_settings_path, notice: "Settings saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def settings_params
    params.require(:user).permit(
      :sailmail_address,
      :relay_imap_server, :relay_imap_port, :relay_imap_username, :relay_imap_password, :relay_imap_use_ssl,
      :relay_smtp_server, :relay_smtp_port, :relay_smtp_username, :relay_smtp_password, :relay_smtp_use_starttls,
      :bundle_ratio, :daily_budget_kb
    )
  end
end
