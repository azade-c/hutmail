class RelayAccount < ApplicationRecord
  include Connectable

  belongs_to :vessel
  has_many :processed_relay_messages, through: :vessel

  validates :imap_username, presence: true
  validates :imap_password, presence: true
  validates :smtp_username, presence: true
  validates :smtp_password, presence: true
end
