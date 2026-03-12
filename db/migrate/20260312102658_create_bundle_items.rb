class CreateBundleItems < ActiveRecord::Migration[8.1]
  def change
    create_table :bundle_items do |t|
      t.references :bundle, null: false, foreign_key: true
      t.references :message_digest, null: false, foreign_key: true
      t.timestamps
    end

    add_index :bundle_items, [ :bundle_id, :message_digest_id ], unique: true
  end
end
