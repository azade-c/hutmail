class AddImapAuthMethodToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :mail_accounts, :imap_auth_method, :string
    add_column :relay_accounts, :imap_auth_method, :string
  end
end
