module Vessel::RelayPolling
  extend ActiveSupport::Concern

  class_methods do
    def poll_all_now
      find_each do |vessel|
        vessel.poll_relay_now
      rescue => e
        Rails.logger.error "Vessel##{vessel.id} relay poll failed: #{e.message}"
      end
    end
  end

  def poll_relay_now
    relay_account.with_imap_connection do |imap|
      imap.select("INBOX")

      uids = imap.search([ "FROM", sailmail_address ])
      return if uids.empty?

      uids.each do |uid|
        data = imap.fetch(uid, [ "ENVELOPE", "BODY.PEEK[]" ])&.first
        next unless data

        message_id = data.attr["ENVELOPE"]&.message_id
        next if message_id.blank?
        next if processed_relay_messages.exists?(imap_message_id: message_id)

        raw = data.attr["BODY[]"]
        mail = Mail.new(raw)
        body = mail.text_part&.decoded || mail.body.decoded.to_s

        results = parse_and_execute_commands(body)
        processed_relay_messages.create!(imap_message_id: message_id)

        imap.store(uid, "+FLAGS", [ :Seen ])

        Rails.logger.info "Vessel##{id} relay poll: processed #{results.size} commands/messages"
      end
    end
  end
end
