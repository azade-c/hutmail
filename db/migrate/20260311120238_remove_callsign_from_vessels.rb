class RemoveCallsignFromVessels < ActiveRecord::Migration[8.1]
  def change
    remove_index :vessels, :callsign
    remove_column :vessels, :callsign, :string, null: false
    change_column_null :vessels, :name, false
  end
end
