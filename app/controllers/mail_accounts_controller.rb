class MailAccountsController < ApplicationController
  before_action :set_mail_account, only: %i[destroy]

  def index
    @mail_accounts = Current.user.mail_accounts.order(:name)
  end

  def new
    @mail_account = Current.user.mail_accounts.build(imap_port: 993, use_ssl: true)
  end

  def create
    @mail_account = Current.user.mail_accounts.build(mail_account_params)

    # Test connection before saving
    result = ImapFetcher.new(@mail_account).test_connection
    unless result.success
      @mail_account.errors.add(:base, "Connection failed: #{result.error}")
      return render :new, status: :unprocessable_entity
    end

    if @mail_account.save
      redirect_to mail_accounts_path, notice: "#{@mail_account.name} added successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @mail_account.destroy
    redirect_to mail_accounts_path, notice: "Account removed."
  end

  private

  def set_mail_account
    @mail_account = Current.user.mail_accounts.find(params[:id])
  end

  def mail_account_params
    params.expect(mail_account: [ :name, :imap_server, :imap_port, :imap_username, :imap_password, :use_ssl ])
  end
end
