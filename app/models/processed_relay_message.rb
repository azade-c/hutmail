class ProcessedRelayMessage < ApplicationRecord
  belongs_to :vessel

  validates :imap_message_id, presence: true, uniqueness: { scope: :vessel_id }
end
