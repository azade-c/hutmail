class CreateCommandResponses < ActiveRecord::Migration[8.1]
  def change
    create_table :command_responses do |t|
      t.references :vessel, null: false, foreign_key: true
      t.references :bundle, foreign_key: true
      t.string :source, null: false
      t.string :command, null: false
      t.text :response_text, null: false
      t.string :status, null: false, default: "pending"
      t.datetime :sent_at
      t.text :error_message

      t.timestamps
    end

    add_index :command_responses, [ :vessel_id, :status ]
  end
end
