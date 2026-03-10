module Vessel::RelayPolling
  extend ActiveSupport::Concern

  def poll_relay_later
    # TODO: fcatuhe 10mar26 add dedicated recurring job if needed
  end

  def poll_relay_now
    return if relay_imap_server.blank?

    with_relay_connection do |imap|
      imap.select("INBOX")

      uids = imap.search([ "UNSEEN", "FROM", sailmail_address ])
      return if uids.empty?

      uids.each do |uid|
        data = imap.fetch(uid, "RFC822")&.first
        next unless data

        raw = data.attr["RFC822"]
        mail = Mail.new(raw)
        body = mail.text_part&.decoded || mail.body.decoded.to_s

        results = parse_and_execute_commands(body)

        imap.store(uid, "+FLAGS", [ :Seen ])

        Rails.logger.info "Vessel##{id} relay poll: processed #{results.size} commands/messages"
      end
    end
  end

  private
    def with_relay_connection
      imap = Net::IMAP.new(relay_imap_server, port: relay_imap_port, ssl: relay_imap_use_ssl)
      imap.login(relay_imap_username, relay_imap_password)
      yield imap
    ensure
      imap&.logout rescue nil
      imap&.disconnect rescue nil
    end
end
