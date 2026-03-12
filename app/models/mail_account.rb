class MailAccount < ApplicationRecord
  include Connectable
  include MailAccount::Collecting

  IMAP_MOVE_STRATEGIES = %w[move copy_delete_expunge].freeze
  IMAP_PROCESSED_FOLDER = "HutMail"

  belongs_to :vessel
  has_many :message_digests, dependent: :destroy
  has_many :vessel_replies, dependent: :destroy

  normalizes :short_code, with: ->(s) { s.strip.upcase }

  validates :name, presence: true
  validates :short_code, presence: true, length: { is: 2 },
    format: { with: /\A[A-Z]{2}\z/, message: "must be 2 uppercase letters" },
    uniqueness: { scope: :vessel_id }
  validates :imap_move_strategy, inclusion: { in: IMAP_MOVE_STRATEGIES }, allow_nil: true

  def mark_as_processed(imap_uids)
    return if imap_uids.empty?

    with_imap_connection do |imap|
      imap.select("INBOX")
      ensure_folder(imap, IMAP_PROCESSED_FOLDER)
      imap.uid_store(imap_uids, "+FLAGS", [ :Seen ])
      apply_imap_move_strategy(imap, imap_uids, IMAP_PROCESSED_FOLDER)
    end
  end

  private
    def ensure_folder(imap, name)
      imap.create(name)
    rescue Net::IMAP::NoResponseError
    end

    def apply_imap_move_strategy(imap, uids, folder)
      strategy = imap_move_strategy.presence || detect_imap_move_strategy(imap, uids, folder)

      if strategy == "move"
        imap.uid_move(uids, folder)
      else
        copy_delete_expunge(imap, uids, folder)
      end
    end

    def detect_imap_move_strategy(imap, uids, folder)
      imap.uid_move(uids, folder)
      update_column(:imap_move_strategy, "move")
      "move"
    rescue Net::IMAP::BadResponseError, Net::IMAP::NoResponseError
      copy_delete_expunge(imap, uids, folder)
      update_column(:imap_move_strategy, "copy_delete_expunge")
      "copy_delete_expunge"
    end

    def copy_delete_expunge(imap, uids, folder)
      imap.uid_copy(uids, folder)
      imap.uid_store(uids, "+FLAGS", [ :Deleted ])
      imap.expunge
    end
end
