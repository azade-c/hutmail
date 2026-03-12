class AddDispatchLogToBundles < ActiveRecord::Migration[8.1]
  def change
    add_column :bundles, :dispatch_log, :text
  end
end
