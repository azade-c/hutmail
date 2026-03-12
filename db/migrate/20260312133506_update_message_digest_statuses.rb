class UpdateMessageDigestStatuses < ActiveRecord::Migration[8.1]
  class MessageDigest < ApplicationRecord
    self.table_name = "message_digests"
  end

  def up
    rename_status "pending", "collected"
    rename_status "sent", "bundled"
    rename_status "resend", "requeued"
    remove_unsupported_status("dropped", "no_longer_collectable")
  end

  def down
    rename_status "collected", "pending"
    rename_status "bundled", "sent"
    rename_status "requeued", "resend"
    rename_status "no_longer_collectable", "pending"
  end

  private
    def rename_status(from, to)
      MessageDigest.where(status: from).update_all(status: to)
    end

    def remove_unsupported_status(from, to)
      MessageDigest.where(status: from).update_all(status: to)
    end
end
