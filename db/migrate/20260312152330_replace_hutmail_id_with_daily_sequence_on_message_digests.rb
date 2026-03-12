class ReplaceHutmailIdWithDailySequenceOnMessageDigests < ActiveRecord::Migration[8.1]
  class MigrationMessageDigest < ApplicationRecord
    self.table_name = "message_digests"
  end

  def up
    add_column :message_digests, :daily_sequence, :integer

    MigrationMessageDigest.reset_column_information
    MigrationMessageDigest.find_each do |message_digest|
      sequence = message_digest.hutmail_id.to_s.split(".").last.to_i
      message_digest.update_columns(daily_sequence: sequence)
    end

    change_column_null :message_digests, :daily_sequence, false
    add_index :message_digests, [ :mail_account_id, :date, :daily_sequence ], unique: true, name: "idx_message_digests_daily_sequence"

    remove_index :message_digests, :hutmail_id
    remove_column :message_digests, :hutmail_id, :string
  end

  def down
    add_column :message_digests, :hutmail_id, :string
    MigrationMessageDigest.reset_column_information

    MigrationMessageDigest.find_each do |message_digest|
      date = message_digest.date.to_date
      year_suffix = date.year != Date.current.year ? date.year.to_s[-2..] : ""
      hutmail_id = format("%<day>02d%<month>s%<year>s.%<code>s.%<sequence>d",
        day: date.day,
        month: %w[jan feb mar apr may jun jul aug sep oct nov dec][date.month - 1],
        year: year_suffix,
        code: MailAccount.find(message_digest.mail_account_id).short_code,
        sequence: message_digest.daily_sequence)
      message_digest.update_columns(hutmail_id: hutmail_id)
    end

    add_index :message_digests, :hutmail_id, unique: true
    remove_index :message_digests, name: "idx_message_digests_daily_sequence"
    remove_column :message_digests, :daily_sequence, :integer
  end
end
