class RenameBoatRepliesToVesselReplies < ActiveRecord::Migration[8.1]
  def change
    rename_table :boat_replies, :vessel_replies
  end
end
