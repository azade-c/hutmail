class AddTrackTokenToVessels < ActiveRecord::Migration[8.1]
  def up
    add_column :vessels, :track_token, :string

    Vessel.reset_column_information
    Vessel.where(track_token: nil).find_each do |vessel|
      vessel.update_columns(track_token: Vessel.generate_unique_secure_token(length: 24))
    end

    change_column_null :vessels, :track_token, false
    add_index :vessels, :track_token, unique: true
  end

  def down
    remove_column :vessels, :track_token
  end
end
