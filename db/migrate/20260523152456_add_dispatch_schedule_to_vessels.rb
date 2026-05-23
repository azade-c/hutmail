class AddDispatchScheduleToVessels < ActiveRecord::Migration[8.1]
  def change
    add_column :vessels, :dispatch_cadence, :string, default: "manual", null: false
    add_column :vessels, :dispatch_every_hours, :integer
    add_column :vessels, :dispatch_daily_at, :string
    add_column :vessels, :dispatch_timezone, :string, default: "UTC", null: false
    add_column :vessels, :next_dispatch_at, :datetime
    add_index :vessels, :next_dispatch_at
    add_column :vessels, :last_dispatched_at, :datetime
  end
end
