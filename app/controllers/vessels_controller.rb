class VesselsController < ApplicationController
  before_action :set_vessel, only: :show

  def index
    @vessels = current_user.vessels.includes(:relay_account, :mail_accounts)
  end

  def new
    @vessel = Vessel.new
    @vessel.build_relay_account
  end

  def create
    @vessel = Vessel.new(vessel_params)
    @vessel.captain = current_user

    if @vessel.save
      redirect_to vessel_path(@vessel), notice: "Bateau créé — bienvenue à bord ! ⛵"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @mail_accounts = @vessel.mail_accounts
    @pending_messages = CollectedMessage.pending
      .joins(:mail_account)
      .where(mail_accounts: { vessel_id: @vessel.id })
      .includes(:mail_account)
      .oldest_first
    @recent_bundles = @vessel.bundles.recent.limit(5)
    @budget_consumed = @vessel.budget_consumed_7d
    @budget_remaining = @vessel.budget_remaining
  end

  private
    def set_vessel
      @vessel = current_user.vessels.find_by(id: params[:id])

      unless @vessel
        redirect_to vessels_path, alert: "Bateau introuvable"
      end
    end

    def vessel_params
      params.require(:vessel).permit(
        :name, :sailmail_address,
        relay_account_attributes: %i[
          imap_server imap_port imap_username imap_password imap_use_ssl
          smtp_server smtp_port smtp_username smtp_password smtp_use_starttls
        ],
      )
    end
end
