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
      account = relay_account
      imap = Net::IMAP.new(account.imap_server, port: account.imap_port, ssl: account.imap_use_ssl)
      imap.login(account.imap_username, account.imap_password)
      yield imap
    ensure
      imap&.logout rescue nil
      imap&.disconnect rescue nil
    end
end
