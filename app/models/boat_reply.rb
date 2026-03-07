class BoatReply < ApplicationRecord
  belongs_to :user
  belongs_to :mail_account

  encrypts :to_address
  encrypts :body

  validates :to_address, presence: true
  validates :status, presence: true, inclusion: { in: %w[pending sent error] }

  scope :pending, -> { where(status: "pending") }
end
