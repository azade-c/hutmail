class AddImapMoveStrategyToRelayAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :relay_accounts, :imap_move_strategy, :string
  end
end
