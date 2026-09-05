class AddSequenceToPositionReports < ActiveRecord::Migration[8.1]
  # Existing reports are numbered along the track, oldest first, which is the
  # order a skipper would have counted them in. The vessel keeps the high-water
  # mark so a number is never handed out twice, not even after the last point
  # of a track has been deleted. Raw SQL rather than the models: a migration has
  # to keep working long after they have moved on.
  def up
    add_column :position_reports, :sequence, :integer
    add_column :vessels, :last_position_sequence, :integer, null: false, default: 0

    select_rows("SELECT id, vessel_id FROM position_reports ORDER BY vessel_id, reported_at, id")
      .group_by(&:last)
      .each do |vessel_id, rows|
        rows.each_with_index do |(id, _vessel_id), index|
          execute "UPDATE position_reports SET sequence = #{index + 1} WHERE id = #{quote(id)}"
        end

        execute <<~SQL.squish
          UPDATE vessels
          SET last_position_sequence = #{rows.size}
          WHERE id = #{quote(vessel_id)}
        SQL
      end

    change_column_null :position_reports, :sequence, false
    add_index :position_reports, [ :vessel_id, :sequence ], unique: true
  end

  # SQLite drops a column by rebuilding the table and replaying its indexes, so
  # the unique pair has to go first: replayed without :sequence it would become
  # a unique index on :vessel_id alone, and a second report would not fit.
  def down
    remove_index :position_reports, [ :vessel_id, :sequence ]
    remove_column :position_reports, :sequence
    remove_column :vessels, :last_position_sequence
  end
end
