class CollectionsController < ApplicationController
  include VesselScoped

  before_action :set_mail_account

  def create
    @mail_account.recollect!
    redirect_to vessel_mail_account_path(@vessel, @mail_account), notice: "Collecte relancée."
  end

  private
    def set_mail_account
      @mail_account = @vessel.mail_accounts.find(params[:mail_account_id])
    end
end
