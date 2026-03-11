class Vessel < ApplicationRecord
  include Vessel::Cycling
  include Vessel::Dispatching
  include Vessel::Commanding
  include Vessel::RelayPolling

  has_many :crews, dependent: :destroy
  has_many :users, through: :crews
  has_many :mail_accounts, dependent: :destroy
  has_many :bundles, dependent: :destroy
  has_many :vessel_replies, dependent: :destroy
  has_many :processed_relay_messages, dependent: :delete_all
  has_one :relay_account, dependent: :destroy

  accepts_nested_attributes_for :relay_account, update_only: true

  validates :name, presence: true
  validates :sailmail_address, presence: true
  validates :relay_account, presence: true
  validates_associated :relay_account
  validates :bundle_ratio, numericality: { in: 1..100 }, allow_nil: true
  validates :daily_budget_kb, numericality: { greater_than: 0 }, allow_nil: true

  attr_accessor :captain

  after_create { crews.create!(user: captain, role: "captain") if captain }

  def budget_consumed_7d
    bundles.where(status: "sent", sent_at: 7.days.ago..).sum(:total_stripped_size)
  end

  def budget_remaining
    [ (daily_budget_kb * 7 * 1024) - budget_consumed_7d, 0 ].max
  end

  def message_budget
    budget_remaining * (bundle_ratio / 100.0)
  end

  def screener_budget
    budget_remaining - message_budget
  end
end
