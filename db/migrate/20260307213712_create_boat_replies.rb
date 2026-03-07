class CreateBoatReplies < ActiveRecord::Migration[8.1]
  def change
    create_table :boat_replies do |t|
      t.references :user, null: false, foreign_key: true
      t.references :mail_account, null: false, foreign_key: true
      t.string :to_address
      t.text :body
      t.datetime :sent_at
      t.string :status
      t.string :error_message

      t.timestamps
    end
  end
end
