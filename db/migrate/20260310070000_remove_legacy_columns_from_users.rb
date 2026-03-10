class RemoveLegacyColumnsFromUsers < ActiveRecord::Migration[8.1]
  def change
    remove_column :users, :sailmail_address, :string
    remove_column :users, :relay_imap_server, :string
    remove_column :users, :relay_imap_port, :integer
    remove_column :users, :relay_imap_username, :string
    remove_column :users, :relay_imap_password, :string
    remove_column :users, :relay_imap_use_ssl, :boolean
    remove_column :users, :relay_smtp_server, :string
    remove_column :users, :relay_smtp_port, :integer
    remove_column :users, :relay_smtp_username, :string
    remove_column :users, :relay_smtp_password, :string
    remove_column :users, :relay_smtp_use_starttls, :boolean
    remove_column :users, :bundle_ratio, :integer, default: 80
    remove_column :users, :daily_budget_kb, :integer, default: 100
  end
end
