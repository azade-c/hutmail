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
      capabilities = imap.capability
      strategy = imap_move_strategy.presence || resolve_move_strategy(capabilities)

      if strategy == "move"
        imap.uid_move(uids, folder)
        strategy
      else
        copy_delete_expunge(imap, uids, folder, capabilities:)
        strategy
      end
    rescue Net::IMAP::BadResponseError, Net::IMAP::NoResponseError
      if strategy == "move"
        update_column(:imap_move_strategy, "copy_delete_expunge")
        copy_delete_expunge(imap, uids, folder, capabilities:)
        "copy_delete_expunge"
      else
        raise
      end
    end

    def resolve_move_strategy(capabilities)
      if capabilities.include?("MOVE")
        update_column(:imap_move_strategy, "move")
        "move"
      else
        update_column(:imap_move_strategy, "copy_delete_expunge")
        "copy_delete_expunge"
      end
    end

    def copy_delete_expunge(imap, uids, folder, capabilities: nil)
      imap.uid_copy(uids, folder)
      imap.uid_store(uids, "+FLAGS", [ :Deleted ])

      caps = capabilities || imap.capability
      if caps.include?("UIDPLUS")
        imap.uid_expunge(uids)
      else
        imap.expunge
      end
    end
end
