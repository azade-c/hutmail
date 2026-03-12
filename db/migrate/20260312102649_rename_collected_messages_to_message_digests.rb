class RenameCollectedMessagesToMessageDigests < ActiveRecord::Migration[8.1]
  def change
    rename_table :collected_messages, :message_digests
  end
end
