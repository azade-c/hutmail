class CreatePositionReports < ActiveRecord::Migration[8.1]
  def change
    create_table :position_reports do |t|
      t.references :vessel, null: false, foreign_key: true
      t.datetime :reported_at, null: false
      t.decimal :latitude, precision: 9, scale: 6, null: false
      t.decimal :longitude, precision: 9, scale: 6, null: false

      t.timestamps
    end

    # A radio link drops and repeats: the same POSREPORT can arrive twice.
    # The timestamp is the natural identity of a fix, so re-sending one
    # updates it instead of doubling the trace.
    add_index :position_reports, %i[vessel_id reported_at], unique: true
  end
end
