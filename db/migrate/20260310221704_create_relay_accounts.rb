class CreateRelayAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :relay_accounts do |t|
      t.references :vessel, null: false, foreign_key: true, index: { unique: true }
      t.string :imap_server
      t.integer :imap_port
      t.string :imap_username
      t.string :imap_password
      t.boolean :imap_use_ssl
      t.string :smtp_server
      t.integer :smtp_port
      t.string :smtp_username
      t.string :smtp_password
      t.boolean :smtp_use_starttls

      t.timestamps
    end
  end
end
