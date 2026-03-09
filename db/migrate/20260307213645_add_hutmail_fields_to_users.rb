class AddHutmailFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :sailmail_address, :string
    add_column :users, :relay_imap_server, :string
    add_column :users, :relay_imap_port, :integer
    add_column :users, :relay_imap_username, :string
    add_column :users, :relay_imap_password, :string
    add_column :users, :relay_imap_use_ssl, :boolean
    add_column :users, :relay_smtp_server, :string
    add_column :users, :relay_smtp_port, :integer
    add_column :users, :relay_smtp_username, :string
    add_column :users, :relay_smtp_password, :string
    add_column :users, :relay_smtp_use_starttls, :boolean
    add_column :users, :bundle_ratio, :integer, default: 80
    add_column :users, :daily_budget_kb, :integer, default: 100
  end
end
