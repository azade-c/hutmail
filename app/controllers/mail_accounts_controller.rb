class MailAccountsController < ApplicationController
  include VesselScoped

  before_action :set_mail_account, only: %i[show edit update destroy]

  def index
    @mail_accounts = @vessel.mail_accounts
  end

  def show
    @messages = @mail_account.collected_messages.oldest_first.limit(50)
  end

  def new
    @mail_account = @vessel.mail_accounts.build
  end

  def create
    @mail_account = @vessel.mail_accounts.build(mail_account_params)

    if @mail_account.save
      redirect_to vessel_mail_account_path(@vessel, @mail_account), notice: "Compte ajouté."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @mail_account.update(mail_account_params)
      redirect_to vessel_mail_account_path(@vessel, @mail_account), notice: "Compte mis à jour."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @mail_account.destroy
    redirect_to vessel_mail_accounts_path(@vessel), notice: "Compte supprimé."
  end

  private
    def set_mail_account
      @mail_account = @vessel.mail_accounts.find(params[:id])
    end

    def mail_account_params
      params.require(:mail_account).permit(
        :name, :short_code,
        :imap_server, :imap_port, :imap_username, :imap_password, :imap_encryption,
        :smtp_server, :smtp_port, :smtp_username, :smtp_password, :smtp_encryption,
        :is_default, :skip_already_read,
      )
    end
end
