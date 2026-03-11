class MailAccount < ApplicationRecord
  include Connectable
  include MailAccount::Collecting

  belongs_to :vessel
  has_many :collected_messages, dependent: :destroy
  has_many :vessel_replies, dependent: :destroy

  normalizes :short_code, with: ->(s) { s.strip.upcase }

  validates :name, presence: true
  validates :short_code, presence: true, length: { is: 2 },
    format: { with: /\A[A-Z]{2}\z/, message: "must be 2 uppercase letters" },
    uniqueness: { scope: :vessel_id }

  def mark_as_read(imap_uids)
    return if imap_uids.empty?

    with_imap_connection do |imap|
      imap.select("INBOX")
      imap.store(imap_uids, "+FLAGS", [ :Seen ])
    end
  end
end
