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

        unless from_vessel?(mail)
          Rails.logger.warn "Vessel##{id} relay poll: refused #{message_id}, From: #{mail.from.inspect} is not the vessel's address"
          next
        end

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

  private
    # IMAP SEARCH FROM is a substring match (RFC 3501), so the search alone also
    # hands us mail from ALB1234@sailmail.com.somewhere-else.tld. Commands can
    # delete a position report, so the From: has to *be* the vessel's address and
    # carry nothing alongside it — one forged co-author would otherwise be enough.
    #
    # This closes the gap between "contains" and "is". It is not authentication:
    # a From: header is unsigned, and anyone who knows both the relay mailbox and
    # the callsign can still write one. Checking DKIM/SPF is the next step up.
    def from_vessel?(mail)
      Array(mail.from).map { |address| address.to_s.strip.downcase } == [ sailmail_address.to_s.strip.downcase ]
    end
end
