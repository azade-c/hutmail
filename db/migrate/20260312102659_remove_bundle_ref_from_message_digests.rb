class RemoveBundleRefFromMessageDigests < ActiveRecord::Migration[8.1]
  def change
    remove_reference :message_digests, :bundle, foreign_key: true, index: true
    remove_column :message_digests, :sent_at, :datetime
  end
end
