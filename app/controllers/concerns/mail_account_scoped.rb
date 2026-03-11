module MailAccountScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_mail_account, :set_vessel
    helper_method :current_vessel
  end

  private
    def set_mail_account
      @mail_account = MailAccount.find(params[:mail_account_id] || params[:id])
    end

    def set_vessel
      @vessel = current_user.vessels.find_by(id: @mail_account.vessel_id)

      unless @vessel
        redirect_to vessels_path, alert: "Bateau introuvable"
      end
    end

    def current_vessel = @vessel
end
