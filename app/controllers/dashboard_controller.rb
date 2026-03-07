class DashboardController < ApplicationController
  def show
    @pending_messages = current_user.mail_accounts
      .joins(:collected_messages)
      .where(collected_messages: { status: "pending" })
      .select("collected_messages.*")
      .order("collected_messages.date ASC")

    @recent_bundles = current_user.bundles.recent.limit(5)
    @budget_consumed = current_user.budget_consumed_7d
    @budget_remaining = current_user.budget_remaining
    @mail_accounts = current_user.mail_accounts
  end
end
