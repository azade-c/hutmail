class RelayPollJob < ApplicationJob
  queue_as :default

  def perform
    User.find_each do |user|
      poll_relay(user)
    rescue => e
      Rails.logger.error "RelayPollJob: User##{user.id} failed: #{e.message}"
    end
  end

  private

  def poll_relay(user)
    return if user.relay_imap_server.blank?

    imap = Net::IMAP.new(user.relay_imap_server, port: user.relay_imap_port, ssl: user.relay_imap_use_ssl)
    imap.login(user.relay_imap_username, user.relay_imap_password)
    imap.select("INBOX")

    uids = imap.search([ "UNSEEN", "FROM", user.sailmail_address ])
    return if uids.empty?

    uids.each do |uid|
      data = imap.fetch(uid, "RFC822")&.first
      next unless data

      raw = data.attr["RFC822"]
      mail = Mail.new(raw)
      body = mail.text_part&.decoded || mail.body.decoded.to_s

      parser = BoatCommandParser.new(user)
      parser.parse_and_execute(body)

      imap.store(uid, "+FLAGS", [ :Seen ])

      Rails.logger.info "RelayPollJob: User##{user.id} processed #{parser.results.size} commands/messages"
    end
  ensure
    imap&.logout rescue nil
    imap&.disconnect rescue nil
  end
end
