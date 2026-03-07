class CreateCollectedMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :collected_messages do |t|
      t.references :mail_account, null: false, foreign_key: true
      t.string :hutmail_id
      t.integer :imap_uid
      t.string :imap_message_id
      t.string :from_address
      t.string :from_name
      t.string :to_address
      t.string :subject
      t.datetime :date
      t.integer :raw_size
      t.text :stripped_body
      t.integer :stripped_size
      t.string :status
      t.datetime :collected_at
      t.datetime :sent_at
      t.references :bundle, foreign_key: true
      t.json :attachments_metadata

      t.timestamps
    end

    add_index :collected_messages, :hutmail_id, unique: true
    add_index :collected_messages, [ :mail_account_id, :imap_message_id ], unique: true, name: "idx_collected_messages_dedup"
    add_index :collected_messages, :status
  end
end
