class AddImapMoveStrategyToMailAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :mail_accounts, :imap_move_strategy, :string
  end
end
