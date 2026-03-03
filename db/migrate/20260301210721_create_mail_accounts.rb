class CreateMailAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :mail_accounts do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :imap_server, null: false
      t.integer :imap_port, null: false, default: 993
      t.string :imap_username, null: false
      t.string :imap_password, null: false
      t.boolean :use_ssl, null: false, default: true

      t.timestamps
    end
  end
end
