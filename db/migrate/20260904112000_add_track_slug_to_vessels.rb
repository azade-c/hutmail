class AddTrackSlugToVessels < ActiveRecord::Migration[8.1]
  # Matches the default drawn by Vessel::Tracking. The backfill goes through raw
  # SQL rather than Vessel: a migration has to keep working long after the model
  # has moved on.
  SLUG_LENGTH = 24

  def up
    add_column :vessels, :track_slug, :string

    select_values("SELECT id FROM vessels WHERE track_slug IS NULL").each do |id|
      execute <<~SQL.squish
        UPDATE vessels
        SET track_slug = #{quote(SecureRandom.base58(SLUG_LENGTH))}
        WHERE id = #{quote(id)}
      SQL
    end

    change_column_null :vessels, :track_slug, false
    add_index :vessels, :track_slug, unique: true
  end

  def down
    remove_column :vessels, :track_slug
  end
end
