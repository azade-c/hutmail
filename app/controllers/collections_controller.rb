class CollectionsController < ApplicationController
  include MailAccountScoped

  def create
    @mail_account.recollect!
    redirect_to mail_account_path(@mail_account), notice: "Collecte relancée."
  end
end
