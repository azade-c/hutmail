class DashboardController < ApplicationController
  def show
    return unless current_vessel

    @pending_messages = current_vessel.mail_accounts
      .joins(:collected_messages)
      .where(collected_messages: { status: "pending" })
      .select("collected_messages.*")
      .order("collected_messages.date ASC")

    @recent_bundles = current_vessel.bundles.recent.limit(5)
    @budget_consumed = current_vessel.budget_consumed_7d
    @budget_remaining = current_vessel.budget_remaining
    @mail_accounts = current_vessel.mail_accounts
  end
end
