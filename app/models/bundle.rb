class Bundle < ApplicationRecord
  include Bundle::Composable

  belongs_to :vessel
  has_many :collected_messages

  validates :status, presence: true, inclusion: { in: %w[draft sent error] }

  scope :sent, -> { where(status: "sent") }
  scope :recent, -> { order(created_at: :desc) }
end
