class Vessels::MailAccountsController < ApplicationController
  include VesselScoped

  def index
    @mail_accounts = @vessel.mail_accounts
  end

  def new
    @mail_account = @vessel.mail_accounts.build
  end

  def create
    @mail_account = @vessel.mail_accounts.build(mail_account_params)

    if @mail_account.save
      redirect_to mail_account_path(@mail_account), notice: "Compte ajouté."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
    def mail_account_params
      params.require(:mail_account).permit(
        :name, :short_code,
        :imap_server, :imap_port, :imap_username, :imap_password, :imap_encryption,
        :smtp_server, :smtp_port, :smtp_username, :smtp_password, :smtp_encryption,
        :is_default, :skip_already_read,
      )
    end
end
