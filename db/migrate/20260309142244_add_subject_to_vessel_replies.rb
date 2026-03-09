class AddSubjectToVesselReplies < ActiveRecord::Migration[8.1]
  def change
    add_column :vessel_replies, :subject, :string
  end
end
