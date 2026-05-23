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
    processed_uids = []

    relay_account.with_imap_connection do |imap|
      imap.select("INBOX")

      uids = imap.uid_search([ "FROM", sailmail_address ])
      next if uids.empty?

      uids.each do |uid|
        data = imap.uid_fetch(uid, [ "ENVELOPE", "BODY.PEEK[]" ])&.first
        next unless data

        message_id = data.attr["ENVELOPE"]&.message_id
        next if message_id.blank?
        next if processed_relay_messages.exists?(imap_message_id: message_id)

        raw = data.attr["BODY[]"]
        mail = Mail.new(raw)
        body = mail.text_part&.decoded || mail.body.decoded.to_s
        subject = mail.subject.to_s

        subject_results = parse_and_execute_subject(subject)
        body_results = parse_and_execute_commands(body)
        processed_relay_messages.create!(imap_message_id: message_id)
        processed_uids << uid

        Rails.logger.info "Vessel##{id} relay poll: processed #{subject_results.size + body_results.size} commands/messages"
      end
    end

    return if processed_uids.empty?

    begin
      relay_account.mark_as_processed(processed_uids)
    rescue => e
      Rails.logger.warn "Vessel##{id} failed to archive relay messages: #{e.class}: #{e.message}"
    end
  end
end
