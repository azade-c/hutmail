class Bundle < ApplicationRecord
  include Bundle::Composing
  include Bundle::Delivering

  belongs_to :vessel
  has_many :bundle_items, dependent: :destroy
  has_many :message_digests, through: :bundle_items

  validates :status, presence: true, inclusion: { in: %w[draft sent error] }

  scope :sent, -> { where(status: "sent") }
  scope :recent, -> { order(created_at: :desc) }
end
