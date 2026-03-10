class MailAccountsController < ApplicationController
  before_action :set_mail_account, only: [ :show, :edit, :update, :destroy ]

  def index
    @mail_accounts = current_vessel.mail_accounts
  end

  def show
    @messages = @mail_account.collected_messages.order(date: :desc).limit(50)
  end

  def new
    @mail_account = current_vessel.mail_accounts.build
  end

  def create
    @mail_account = current_vessel.mail_accounts.build(mail_account_params)

    if @mail_account.save
      redirect_to @mail_account, notice: "Account added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @mail_account.update(mail_account_params)
      redirect_to @mail_account, notice: "Account updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @mail_account.destroy
    redirect_to mail_accounts_path, notice: "Account removed."
  end

  private
    def set_mail_account
      @mail_account = current_vessel.mail_accounts.find(params[:id])
    end

    def mail_account_params
      params.require(:mail_account).permit(
        :name, :short_code,
        :imap_server, :imap_port, :imap_username, :imap_password, :imap_use_ssl,
        :smtp_server, :smtp_port, :smtp_username, :smtp_password, :smtp_use_starttls,
        :is_default, :skip_already_read,
      )
    end
end
