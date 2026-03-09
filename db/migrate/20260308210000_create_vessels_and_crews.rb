require "securerandom"

class CreateVesselsAndCrews < ActiveRecord::Migration[8.1]
  class User < ActiveRecord::Base
    self.table_name = "users"
  end

  class Vessel < ActiveRecord::Base
    self.table_name = "vessels"
  end

  class Crew < ActiveRecord::Base
    self.table_name = "crews"
  end

  class MailAccount < ActiveRecord::Base
    self.table_name = "mail_accounts"
  end

  class Bundle < ActiveRecord::Base
    self.table_name = "bundles"
  end

  class BoatReply < ActiveRecord::Base
    self.table_name = "boat_replies"
  end

  def up
    create_table :vessels do |t|
      t.string :name
      t.string :callsign, null: false
      t.string :sailmail_address
      t.string :relay_imap_server
      t.integer :relay_imap_port
      t.string :relay_imap_username
      t.string :relay_imap_password
      t.boolean :relay_imap_use_ssl
      t.string :relay_smtp_server
      t.integer :relay_smtp_port
      t.string :relay_smtp_username
      t.string :relay_smtp_password
      t.boolean :relay_smtp_use_starttls
      t.integer :bundle_ratio, default: 80
      t.integer :daily_budget_kb, default: 100

      t.timestamps
    end

    add_index :vessels, :callsign, unique: true

    create_table :crews do |t|
      t.references :user, null: false, foreign_key: true
      t.references :vessel, null: false, foreign_key: true
      t.string :role, null: false, default: "captain"

      t.timestamps
    end

    add_index :crews, [ :user_id, :vessel_id ], unique: true

    add_reference :mail_accounts, :vessel, foreign_key: true
    add_reference :bundles, :vessel, foreign_key: true
    add_reference :boat_replies, :vessel, foreign_key: true

    backfill_vessels_and_crews

    change_column_null :mail_accounts, :vessel_id, false
    change_column_null :bundles, :vessel_id, false
    change_column_null :boat_replies, :vessel_id, false

    add_index :mail_accounts, [ :vessel_id, :short_code ], unique: true

    remove_index :mail_accounts, name: "index_mail_accounts_on_user_id_and_short_code"
    remove_index :mail_accounts, :user_id
    remove_column :mail_accounts, :user_id

    remove_index :bundles, :user_id
    remove_column :bundles, :user_id

    remove_index :boat_replies, :user_id
    remove_column :boat_replies, :user_id
  end

  def down
    add_reference :mail_accounts, :user, null: true, foreign_key: true
    add_reference :bundles, :user, null: true, foreign_key: true
    add_reference :boat_replies, :user, null: true, foreign_key: true

    remove_column :mail_accounts, :vessel_id
    remove_column :bundles, :vessel_id
    remove_column :boat_replies, :vessel_id

    drop_table :crews
    drop_table :vessels
  end

  private

  def backfill_vessels_and_crews
    User.find_each do |user|
      callsign = extract_callsign(user.sailmail_address)
      callsign = "#{callsign}#{user.id}" if Vessel.exists?(callsign: callsign)

      vessel = Vessel.create!(
        name: user.email_address,
        callsign: callsign,
        sailmail_address: user.sailmail_address.presence || "#{callsign}@sailmail.com",
        relay_imap_server: user.relay_imap_server,
        relay_imap_port: user.relay_imap_port,
        relay_imap_username: user.relay_imap_username,
        relay_imap_password: user.relay_imap_password,
        relay_imap_use_ssl: user.relay_imap_use_ssl,
        relay_smtp_server: user.relay_smtp_server,
        relay_smtp_port: user.relay_smtp_port,
        relay_smtp_username: user.relay_smtp_username,
        relay_smtp_password: user.relay_smtp_password,
        relay_smtp_use_starttls: user.relay_smtp_use_starttls,
        bundle_ratio: user.bundle_ratio,
        daily_budget_kb: user.daily_budget_kb
      )

      Crew.create!(user_id: user.id, vessel_id: vessel.id, role: "captain")

      MailAccount.where(user_id: user.id).update_all(vessel_id: vessel.id)
      Bundle.where(user_id: user.id).update_all(vessel_id: vessel.id)
      BoatReply.where(user_id: user.id).update_all(vessel_id: vessel.id)
    end
  end

  def extract_callsign(sailmail_address)
    return "VESSEL#{SecureRandom.hex(3).upcase}" if sailmail_address.blank?

    sailmail_address.split("@").first.upcase
  end
end
