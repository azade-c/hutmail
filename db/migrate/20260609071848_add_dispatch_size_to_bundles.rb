class AddDispatchSizeToBundles < ActiveRecord::Migration[8.1]
  def up
    add_column :bundles, :dispatch_size, :integer

    # Backfill the real transmitted weight for already-sent bundles so the
    # rolling 7-day budget reflects what actually went over the radio link
    # (the bundle text), not the abstract sum of stripped message bodies.
    execute <<~SQL.squish
      UPDATE bundles
      SET dispatch_size = LENGTH(CAST(bundle_text AS BLOB))
      WHERE bundle_text IS NOT NULL
    SQL
  end

  def down
    remove_column :bundles, :dispatch_size
  end
end
