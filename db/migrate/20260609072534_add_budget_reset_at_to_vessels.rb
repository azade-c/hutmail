class AddBudgetResetAtToVessels < ActiveRecord::Migration[8.1]
  def change
    add_column :vessels, :budget_reset_at, :datetime
  end
end
