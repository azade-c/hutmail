class AddMessageCharLimitToVessels < ActiveRecord::Migration[8.1]
  def change
    add_column :vessels, :message_char_limit, :integer
  end
end
