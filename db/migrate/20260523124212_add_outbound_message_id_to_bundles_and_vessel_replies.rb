class AddOutboundMessageIdToBundlesAndVesselReplies < ActiveRecord::Migration[8.1]
  def change
    add_column :bundles, :outbound_message_id, :string
    add_index :bundles, :outbound_message_id

    add_column :vessel_replies, :outbound_message_id, :string
    add_index :vessel_replies, :outbound_message_id
  end
end
