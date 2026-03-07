class MailAccount < ApplicationRecord
  belongs_to :user
  has_many :collected_messages, dependent: :destroy
  has_many :boat_replies, dependent: :destroy

  encrypts :imap_password
  encrypts :smtp_password

  normalizes :short_code, with: ->(s) { s.strip.upcase }

  validates :name, presence: true
  validates :short_code, presence: true, length: { is: 2 },
    format: { with: /\A[A-Z]{2}\z/, message: "must be 2 uppercase letters" },
    uniqueness: { scope: :user_id }
  validates :imap_server, presence: true
  validates :imap_port, presence: true
  validates :smtp_server, presence: true
  validates :smtp_port, presence: true
end
