class CreateBundles < ActiveRecord::Migration[8.1]
  def change
    create_table :bundles do |t|
      t.references :user, null: false, foreign_key: true
      t.datetime :sent_at
      t.integer :total_raw_size
      t.integer :total_stripped_size
      t.text :bundle_text
      t.string :status
      t.string :error_message
      t.integer :messages_count
      t.integer :remaining_count

      t.timestamps
    end
  end
end
