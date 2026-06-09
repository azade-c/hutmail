class AddBudgetTopupBytesToVessels < ActiveRecord::Migration[8.1]
  def change
    add_column :vessels, :budget_topup_bytes, :integer, null: false, default: 0
  end
end
