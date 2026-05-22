class AddMessageDigestToVesselReplies < ActiveRecord::Migration[8.1]
  def change
    add_reference :vessel_replies, :message_digest, null: true, foreign_key: true
  end
end
