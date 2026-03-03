class ImapFetcher
  require "net/imap"

  Result = Data.define(:success, :emails, :error)
  Email = Data.define(:uid, :from, :to, :subject, :date, :size, :body_preview, :body_full, :seen)

  MAX_EMAILS = 50
  PREVIEW_LENGTH = 200

  def initialize(mail_account)
    @account = mail_account
  end

  def fetch
    imap = Net::IMAP.new(@account.imap_server, port: @account.imap_port, ssl: @account.use_ssl)
    imap.login(@account.imap_username, @account.imap_password)
    imap.select("INBOX")

    # Search for recent messages (last 30 days)
    since_date = 30.days.ago.strftime("%d-%b-%Y")
    uids = imap.uid_search([ "SINCE", since_date ])
    uids = uids.last(MAX_EMAILS)

    emails = []

    if uids.any?
      fetch_data = imap.uid_fetch(uids, [
        "UID", "FLAGS", "ENVELOPE", "RFC822.SIZE", "RFC822"
      ])

      fetch_data&.each do |msg|
        envelope = msg.attr["ENVELOPE"]
        next unless envelope

        from = extract_address(envelope.from)
        to = extract_address(envelope.to)
        subject = decode_subject(envelope.subject)
        date = parse_date(envelope.date)
        size = msg.attr["RFC822.SIZE"] || 0
        flags = msg.attr["FLAGS"] || []

        # Parse full message with Mail gem
        raw_rfc822 = msg.attr["RFC822"] || ""
        body_full = extract_body(raw_rfc822)
        body_preview = body_full.gsub(/\s+/, " ").strip.truncate(PREVIEW_LENGTH)

        emails << Email.new(
          uid: msg.attr["UID"],
          from: from,
          to: to,
          subject: subject,
          date: date,
          size: size,
          body_preview: body_preview,
          body_full: body_full,
          seen: flags.include?(:Seen)
        )
      end
    end

    imap.logout
    imap.disconnect

    Result.new(success: true, emails: emails.reverse, error: nil)
  rescue Net::IMAP::Error, Net::IMAP::NoResponseError, Net::IMAP::BadResponseError => e
    Result.new(success: false, emails: [], error: "IMAP error: #{e.message}")
  rescue SocketError, Errno::ECONNREFUSED, Errno::ETIMEDOUT, OpenSSL::SSL::SSLError => e
    Result.new(success: false, emails: [], error: "Connection error: #{e.message}")
  rescue => e
    Result.new(success: false, emails: [], error: "Unexpected error: #{e.message}")
  ensure
    begin; imap&.disconnect; rescue; end
  end

  def test_connection
    imap = Net::IMAP.new(@account.imap_server, port: @account.imap_port, ssl: @account.use_ssl)
    imap.login(@account.imap_username, @account.imap_password)
    imap.logout
    imap.disconnect
    Result.new(success: true, emails: [], error: nil)
  rescue => e
    Result.new(success: false, emails: [], error: e.message)
  ensure
    begin; imap&.disconnect; rescue; end
  end

  private

  def extract_address(addresses)
    return "" unless addresses&.first
    addr = addresses.first
    if addr.name
      "#{decode_subject(addr.name)} <#{addr.mailbox}@#{addr.host}>"
    else
      "#{addr.mailbox}@#{addr.host}"
    end
  end

  def decode_subject(str)
    return "" unless str
    Mail::Encodings.value_decode(str)
  rescue
    str
  end

  def parse_date(date_str)
    return nil unless date_str
    Time.parse(date_str)
  rescue
    nil
  end

  # Parse the full RFC822 message and extract clean plain text body
  def extract_body(raw_rfc822)
    mail = Mail.new(raw_rfc822)

    text = if mail.multipart?
      # Prefer text/plain part
      plain_part = mail.text_part
      html_part = mail.html_part

      if plain_part
        decode_part(plain_part)
      elsif html_part
        html_to_text(decode_part(html_part))
      else
        # Try all parts, take first text-ish one
        mail.parts.each do |part|
          if part.content_type&.start_with?("text/plain")
            return decode_part(part)
          elsif part.content_type&.start_with?("text/html")
            return html_to_text(decode_part(part))
          end
        end
        ""
      end
    else
      body = mail.body.decoded.force_encoding("UTF-8") rescue mail.body.to_s
      if mail.content_type&.include?("text/html")
        html_to_text(body)
      else
        body
      end
    end

    text.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
  rescue => e
    "(could not parse body: #{e.message})"
  end

  def decode_part(part)
    part.body.decoded.force_encoding(part.charset || "UTF-8")
  rescue
    part.body.to_s
  end

  def html_to_text(html)
    text = html.dup
    # Block-level elements → newlines
    text.gsub!(/<br\s*\/?>/i, "\n")
    text.gsub!(/<\/(p|div|tr|li|h[1-6])>/i, "\n")
    text.gsub!(/<(p|div|tr|li|h[1-6])[^>]*>/i, "\n")
    # Links: keep text and URL
    text.gsub!(/<a[^>]*href="([^"]*)"[^>]*>(.*?)<\/a>/im) { "#{$2} (#{$1})" }
    # Strip all remaining tags
    text.gsub!(/<[^>]+>/, "")
    # Decode entities
    text.gsub!("&nbsp;", " ")
    text.gsub!("&amp;", "&")
    text.gsub!("&lt;", "<")
    text.gsub!("&gt;", ">")
    text.gsub!("&quot;", '"')
    text.gsub!("&#39;", "'")
    text.gsub!(/&#(\d+);/) { [$1.to_i].pack("U") }
    text
  end
end
