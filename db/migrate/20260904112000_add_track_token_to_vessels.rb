class AddTrackTokenToVessels < ActiveRecord::Migration[8.1]
  # Matches has_secure_token :track_token, length: 24. The backfill goes through
  # raw SQL rather than Vessel: a migration has to keep working long after the
  # model has moved on.
  TOKEN_LENGTH = 24

  def up
    add_column :vessels, :track_token, :string

    select_values("SELECT id FROM vessels WHERE track_token IS NULL").each do |id|
      execute <<~SQL.squish
        UPDATE vessels
        SET track_token = #{quote(SecureRandom.base58(TOKEN_LENGTH))}
        WHERE id = #{quote(id)}
      SQL
    end

    change_column_null :vessels, :track_token, false
    add_index :vessels, :track_token, unique: true
  end

  def down
    remove_column :vessels, :track_token
  end
end
