# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_03_09_142244) do
  create_table "bundles", force: :cascade do |t|
    t.text "bundle_text"
    t.datetime "created_at", null: false
    t.string "error_message"
    t.integer "messages_count"
    t.integer "remaining_count"
    t.datetime "sent_at"
    t.string "status"
    t.integer "total_raw_size"
    t.integer "total_stripped_size"
    t.datetime "updated_at", null: false
    t.integer "vessel_id", null: false
    t.index ["vessel_id"], name: "index_bundles_on_vessel_id"
  end

  create_table "collected_messages", force: :cascade do |t|
    t.json "attachments_metadata"
    t.integer "bundle_id"
    t.datetime "collected_at"
    t.datetime "created_at", null: false
    t.datetime "date"
    t.string "from_address"
    t.string "from_name"
    t.string "hutmail_id"
    t.string "imap_message_id"
    t.integer "imap_uid"
    t.integer "mail_account_id", null: false
    t.integer "raw_size"
    t.datetime "sent_at"
    t.string "status"
    t.text "stripped_body"
    t.integer "stripped_size"
    t.string "subject"
    t.string "to_address"
    t.datetime "updated_at", null: false
    t.index ["bundle_id"], name: "index_collected_messages_on_bundle_id"
    t.index ["hutmail_id"], name: "index_collected_messages_on_hutmail_id", unique: true
    t.index ["mail_account_id", "imap_message_id"], name: "idx_collected_messages_dedup", unique: true
    t.index ["mail_account_id"], name: "index_collected_messages_on_mail_account_id"
    t.index ["status"], name: "index_collected_messages_on_status"
  end

  create_table "crews", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "role", default: "captain", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "vessel_id", null: false
    t.index ["user_id", "vessel_id"], name: "index_crews_on_user_id_and_vessel_id", unique: true
    t.index ["user_id"], name: "index_crews_on_user_id"
    t.index ["vessel_id"], name: "index_crews_on_vessel_id"
  end

  create_table "mail_accounts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "imap_password"
    t.integer "imap_port"
    t.string "imap_server"
    t.boolean "imap_use_ssl"
    t.string "imap_username"
    t.boolean "is_default", default: false
    t.string "name"
    t.string "short_code"
    t.boolean "skip_already_read", default: true
    t.string "smtp_password"
    t.integer "smtp_port"
    t.string "smtp_server"
    t.boolean "smtp_use_starttls"
    t.string "smtp_username"
    t.datetime "updated_at", null: false
    t.integer "vessel_id", null: false
    t.index ["vessel_id", "short_code"], name: "index_mail_accounts_on_vessel_id_and_short_code", unique: true
    t.index ["vessel_id"], name: "index_mail_accounts_on_vessel_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.integer "bundle_ratio", default: 80
    t.datetime "created_at", null: false
    t.integer "daily_budget_kb", default: 100
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.string "relay_imap_password"
    t.integer "relay_imap_port"
    t.string "relay_imap_server"
    t.boolean "relay_imap_use_ssl"
    t.string "relay_imap_username"
    t.string "relay_smtp_password"
    t.integer "relay_smtp_port"
    t.string "relay_smtp_server"
    t.boolean "relay_smtp_use_starttls"
    t.string "relay_smtp_username"
    t.string "sailmail_address"
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  create_table "vessel_replies", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "error_message"
    t.integer "mail_account_id", null: false
    t.datetime "sent_at"
    t.string "status"
    t.string "subject"
    t.string "to_address"
    t.datetime "updated_at", null: false
    t.integer "vessel_id", null: false
    t.index ["mail_account_id"], name: "index_vessel_replies_on_mail_account_id"
    t.index ["vessel_id"], name: "index_vessel_replies_on_vessel_id"
  end

  create_table "vessels", force: :cascade do |t|
    t.integer "bundle_ratio", default: 80
    t.string "callsign", null: false
    t.datetime "created_at", null: false
    t.integer "daily_budget_kb", default: 100
    t.string "name"
    t.string "relay_imap_password"
    t.integer "relay_imap_port"
    t.string "relay_imap_server"
    t.boolean "relay_imap_use_ssl"
    t.string "relay_imap_username"
    t.string "relay_smtp_password"
    t.integer "relay_smtp_port"
    t.string "relay_smtp_server"
    t.boolean "relay_smtp_use_starttls"
    t.string "relay_smtp_username"
    t.string "sailmail_address"
    t.datetime "updated_at", null: false
    t.index ["callsign"], name: "index_vessels_on_callsign", unique: true
  end

  add_foreign_key "bundles", "vessels"
  add_foreign_key "collected_messages", "bundles"
  add_foreign_key "collected_messages", "mail_accounts"
  add_foreign_key "crews", "users"
  add_foreign_key "crews", "vessels"
  add_foreign_key "mail_accounts", "vessels"
  add_foreign_key "sessions", "users"
  add_foreign_key "vessel_replies", "mail_accounts"
  add_foreign_key "vessel_replies", "vessels"
end
