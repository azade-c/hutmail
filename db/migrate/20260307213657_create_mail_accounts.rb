class CreateMailAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :mail_accounts do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name
      t.string :short_code
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
      t.boolean :is_default, default: false
      t.boolean :skip_already_read, default: true

      t.timestamps
    end

    add_index :mail_accounts, [ :user_id, :short_code ], unique: true
  end
end
