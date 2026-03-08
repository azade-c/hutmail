class MailAccount < ApplicationRecord
  include MailAccount::Collecting

  belongs_to :vessel
  has_many :collected_messages, dependent: :destroy
  has_many :boat_replies, dependent: :destroy

  encrypts :imap_password
  encrypts :smtp_password

  normalizes :short_code, with: ->(s) { s.strip.upcase }

  validates :name, presence: true
  validates :short_code, presence: true, length: { is: 2 },
    format: { with: /\A[A-Z]{2}\z/, message: "must be 2 uppercase letters" },
    uniqueness: { scope: :vessel_id }
  validates :imap_server, presence: true
  validates :imap_port, presence: true
  validates :smtp_server, presence: true
  validates :smtp_port, presence: true

  def mark_as_read(imap_uids)
    return if imap_uids.empty?

    imap = Net::IMAP.new(imap_server, port: imap_port, ssl: imap_use_ssl)
    imap.login(imap_username, imap_password)
    imap.select("INBOX")
    imap.store(imap_uids, "+FLAGS", [ :Seen ])
  ensure
    imap&.logout rescue nil
    imap&.disconnect rescue nil
  end
end
