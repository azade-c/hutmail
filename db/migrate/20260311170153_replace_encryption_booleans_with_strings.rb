class ReplaceEncryptionBooleansWithStrings < ActiveRecord::Migration[8.1]
  def up
    add_column :mail_accounts, :imap_encryption, :string, default: "ssl", null: false
    add_column :mail_accounts, :smtp_encryption, :string, default: "ssl", null: false
    add_column :relay_accounts, :imap_encryption, :string, default: "ssl", null: false
    add_column :relay_accounts, :smtp_encryption, :string, default: "ssl", null: false

    execute <<~SQL
      UPDATE mail_accounts SET imap_encryption = CASE WHEN imap_use_ssl = 1 THEN 'ssl' ELSE 'none' END
    SQL
    execute <<~SQL
      UPDATE mail_accounts SET smtp_encryption = CASE WHEN smtp_use_starttls = 1 THEN 'starttls' ELSE 'none' END
    SQL
    execute <<~SQL
      UPDATE relay_accounts SET imap_encryption = CASE WHEN imap_use_ssl = 1 THEN 'ssl' ELSE 'none' END
    SQL
    execute <<~SQL
      UPDATE relay_accounts SET smtp_encryption = CASE WHEN smtp_use_starttls = 1 THEN 'starttls' ELSE 'none' END
    SQL

    remove_column :mail_accounts, :imap_use_ssl
    remove_column :mail_accounts, :smtp_use_starttls
    remove_column :relay_accounts, :imap_use_ssl
    remove_column :relay_accounts, :smtp_use_starttls
  end

  def down
    add_column :mail_accounts, :imap_use_ssl, :boolean
    add_column :mail_accounts, :smtp_use_starttls, :boolean
    add_column :relay_accounts, :imap_use_ssl, :boolean
    add_column :relay_accounts, :smtp_use_starttls, :boolean

    execute <<~SQL
      UPDATE mail_accounts SET imap_use_ssl = CASE WHEN imap_encryption = 'ssl' THEN 1 ELSE 0 END
    SQL
    execute <<~SQL
      UPDATE mail_accounts SET smtp_use_starttls = CASE WHEN smtp_encryption = 'starttls' THEN 1 ELSE 0 END
    SQL
    execute <<~SQL
      UPDATE relay_accounts SET imap_use_ssl = CASE WHEN imap_encryption = 'ssl' THEN 1 ELSE 0 END
    SQL
    execute <<~SQL
      UPDATE relay_accounts SET smtp_use_starttls = CASE WHEN smtp_encryption = 'starttls' THEN 1 ELSE 0 END
    SQL

    remove_column :mail_accounts, :imap_encryption
    remove_column :mail_accounts, :smtp_encryption
    remove_column :relay_accounts, :imap_encryption
    remove_column :relay_accounts, :smtp_encryption
  end
end
