class MailAccount < ApplicationRecord
  include Connectable
  include MailAccount::Collecting

  belongs_to :vessel
  has_many :message_digests, dependent: :destroy
  has_many :vessel_replies, dependent: :destroy

  normalizes :short_code, with: ->(s) { s.strip.upcase }

  validates :name, presence: true
  validates :short_code, presence: true, length: { is: 2 },
    format: { with: /\A[A-Z]{2}\z/, message: "must be 2 uppercase letters" },
    uniqueness: { scope: :vessel_id }

  IMAP_PROCESSED_FOLDER = "HutMail"

  def mark_as_processed(imap_uids)
    return if imap_uids.empty?

    with_imap_connection do |imap|
      imap.select("INBOX")
      ensure_folder(imap, IMAP_PROCESSED_FOLDER)
      imap.store(imap_uids, "+FLAGS", [ :Seen ])
      imap.move(imap_uids, IMAP_PROCESSED_FOLDER)
    end
  end

  private
    def ensure_folder(imap, name)
      imap.create(name)
    rescue Net::IMAP::NoResponseError
      # folder already exists
    end
end
