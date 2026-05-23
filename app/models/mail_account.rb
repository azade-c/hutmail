class MailAccount < ApplicationRecord
  include Connectable
  include MailAccount::Collecting

  PROCESSED_FOLDER = "HutMail"

  belongs_to :vessel
  has_many :message_digests, dependent: :destroy
  has_many :vessel_replies, dependent: :destroy

  normalizes :short_code, with: ->(s) { s.strip.upcase }

  validates :name, presence: true
  validates :short_code, presence: true, length: { is: 2 },
    format: { with: /\A[A-Z]{2}\z/, message: "must be 2 uppercase letters" },
    uniqueness: { scope: :vessel_id }
end
