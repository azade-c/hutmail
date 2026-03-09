class RelayPollJob < ApplicationJob
  queue_as :default

  def perform
    Vessel.find_each do |vessel|
      poll_relay(vessel)
    rescue => e
      Rails.logger.error "RelayPollJob: Vessel##{vessel.id} failed: #{e.message}"
    end
  end

  private

  def poll_relay(vessel)
    return if vessel.relay_imap_server.blank?

    imap = Net::IMAP.new(vessel.relay_imap_server, port: vessel.relay_imap_port, ssl: vessel.relay_imap_use_ssl)
    imap.login(vessel.relay_imap_username, vessel.relay_imap_password)
    imap.select("INBOX")

    uids = imap.search([ "UNSEEN", "FROM", vessel.sailmail_address ])
    return if uids.empty?

    uids.each do |uid|
      data = imap.fetch(uid, "RFC822")&.first
      next unless data

      raw = data.attr["RFC822"]
      mail = Mail.new(raw)
      body = mail.text_part&.decoded || mail.body.decoded.to_s

      results = vessel.parse_and_execute_commands(body)

      imap.store(uid, "+FLAGS", [ :Seen ])

      Rails.logger.info "RelayPollJob: Vessel##{vessel.id} processed #{results.size} commands/messages"
    end
  ensure
    imap&.logout rescue nil
    imap&.disconnect rescue nil
  end
end
