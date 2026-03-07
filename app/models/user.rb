class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :mail_accounts, dependent: :destroy
  has_many :bundles, dependent: :destroy
  has_many :boat_replies, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  encrypts :relay_imap_password
  encrypts :relay_smtp_password

  validates :bundle_ratio, numericality: { in: 1..100 }, allow_nil: true
  validates :daily_budget_kb, numericality: { greater_than: 0 }, allow_nil: true

  def budget_consumed_7d
    bundles.where(status: "sent", sent_at: 7.days.ago..).sum(:total_stripped_size)
  end

  def budget_remaining
    (daily_budget_kb * 7 * 1024) - budget_consumed_7d
  end

  def message_budget
    budget_remaining * (bundle_ratio / 100.0)
  end

  def screener_budget
    budget_remaining - message_budget
  end
end
