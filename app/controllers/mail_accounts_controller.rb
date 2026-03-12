class MailAccountsController < ApplicationController
  include MailAccountScoped

  def show
    @messages = @mail_account.message_digests.ordered.limit(50)
  end

  def edit
  end

  def update
    if @mail_account.update(mail_account_params)
      redirect_to mail_account_path(@mail_account), notice: "Compte mis à jour."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    vessel = @vessel
    @mail_account.destroy
    redirect_to vessel_mail_accounts_path(vessel), notice: "Compte supprimé."
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
