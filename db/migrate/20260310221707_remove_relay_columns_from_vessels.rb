class RemoveRelayColumnsFromVessels < ActiveRecord::Migration[8.1]
  def change
    remove_column :vessels, :relay_imap_server, :string
    remove_column :vessels, :relay_imap_port, :integer
    remove_column :vessels, :relay_imap_username, :string
    remove_column :vessels, :relay_imap_password, :string
    remove_column :vessels, :relay_imap_use_ssl, :boolean
    remove_column :vessels, :relay_smtp_server, :string
    remove_column :vessels, :relay_smtp_port, :integer
    remove_column :vessels, :relay_smtp_username, :string
    remove_column :vessels, :relay_smtp_password, :string
    remove_column :vessels, :relay_smtp_use_starttls, :boolean
  end
end
