class CreateProcessedRelayMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :processed_relay_messages do |t|
      t.references :vessel, null: false, foreign_key: true
      t.string :imap_message_id, null: false

      t.timestamps
    end

    add_index :processed_relay_messages, [ :vessel_id, :imap_message_id ], unique: true, name: "idx_processed_relay_dedup"
  end
end
