class VesselReply < ApplicationRecord
  include VesselReply::Deliverable

  self.table_name = "vessel_replies"

  belongs_to :vessel
  belongs_to :mail_account

  encrypts :body

  validates :to_address, presence: true
  validates :status, presence: true, inclusion: { in: %w[pending sent error] }

  scope :pending, -> { where(status: "pending") }
end
