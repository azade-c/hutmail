class DashboardController < ApplicationController
  def show
    return unless current_vessel

    @pending_messages = CollectedMessage.pending
      .joins(:mail_account)
      .where(mail_accounts: { vessel_id: current_vessel.id })
      .includes(:mail_account)
      .oldest_first

    @recent_bundles = current_vessel.bundles.recent.limit(5)
    @budget_consumed = current_vessel.budget_consumed_7d
    @budget_remaining = current_vessel.budget_remaining
    @mail_accounts = current_vessel.mail_accounts
  end
end
