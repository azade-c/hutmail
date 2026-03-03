class SailmailComposer
  SAILMAIL_MAX_SIZE = 35 * 1024 # 35 KB per message

  SIGNATURE_PATTERNS = [
    /^--\s*$/,
    /^_{3,}\s*$/,
    /^-{3,}\s*$/,
    /^Sent from my /i,
    /^Envoyé de mon /i,
    /^Envoyé depuis /i,
    /^Get Outlook for /i,
    /^Télécharger Outlook/i,
    /^Sent from Mail for /i,
    /^Sent from Yahoo Mail/i,
    /^Sent via /i,
  ].freeze

  QUOTE_PATTERNS = [
    /^>+ /,
    /^On .+ wrote:\s*$/i,
    /^Le .+ a écrit\s*:\s*$/i,
    /^De\s*:.*$/i,
    /^From\s*:.*$/i,
    /^-{2,}\s*Original Message/i,
    /^-{2,}\s*Message d'origine/i,
    /^-{2,}\s*Forwarded message/i,
    /^-{2,}\s*Message transféré/i,
    /^Begin forwarded message/i,
  ].freeze

  NOISE_PATTERNS = [
    /^(Disclaimer|Confidential|This email|Ce message|AVERTISSEMENT)/i,
    /^If you are not the intended recipient/i,
    /^Si vous n'êtes pas le destinataire/i,
    /^This message contains confidential/i,
    /^Unsubscribe|Se désabonner|Manage preferences/i,
    /^View this email in your browser/i,
    /^Voir cet email dans votre navigateur/i,
    /^\[image:/i,
    /^\[cid:/i,
    /^https?:\/\/\S+$/,
  ].freeze

  # Bundle emails from multiple accounts into a single delivery.
  #
  # accounts_with_emails: { mail_account => [emails] }
  #
  # Returns: { text:, size:, accounts: [{ name:, email_count:, parts: }], warnings: [] }
  def self.bundle(accounts_with_emails)
    all_empty = accounts_with_emails.values.all?(&:empty?)
    return { text: "(no messages)", size: 0, accounts: [], warnings: [] } if all_empty

    lines = []
    lines << "=== HUTMAIL #{Time.current.strftime('%d/%m %H:%M')} ==="

    account_summaries = []
    global_idx = 0

    accounts_with_emails.each do |account, emails|
      next if emails.empty?

      account_name = account.respond_to?(:name) ? account.name : account.to_s
      account_email = account.respond_to?(:imap_username) ? account.imap_username : ""

      lines << ""
      lines << "==[ #{account_name} (#{account_email}) ]=="
      lines << ""

      parts = []
      emails.each do |email|
        global_idx += 1

        from = extract_email_only(email.from)
        subject = email.subject.presence || "(sans objet)"
        date = email.date&.strftime("%d/%m %H:%M") || "?"

        raw_body = email.respond_to?(:body_full) && email.body_full.present? ? email.body_full : email.body_preview
        body = strip_message(raw_body)

        header = "##{global_idx} From: #{from} | #{subject} | #{date}"
        part_text = "#{header}\n#{body}\n"

        parts << {
          index: global_idx,
          from: from,
          subject: subject,
          body: body,
          size: part_text.bytesize,
          original_size: email.size,
          compression_ratio: email.size > 0 ? ((1 - part_text.bytesize.to_f / email.size) * 100).round(0) : 0
        }

        lines << part_text
      end

      account_summaries << {
        name: account_name,
        email: account_email,
        email_count: emails.size,
        parts: parts
      }
    end

    lines << "=== END (#{global_idx} messages) ==="
    text = lines.join("\n")

    warnings = []
    if text.bytesize > SAILMAIL_MAX_SIZE
      over_kb = format("%.1f", text.bytesize / 1024.0)
      warnings << "⚠ Total #{over_kb} KB exceeds SailMail 35 KB limit. The delivery will be split into multiple messages or truncated."
    end

    { text: text, size: text.bytesize, accounts: account_summaries, warnings: warnings, message_count: global_idx }
  end

  # Strip a message body aggressively for radio transmission
  def self.strip_message(body)
    return "" if body.blank?

    text = body.dup

    # --- HTML cleanup ---
    text.gsub!(/<style[^>]*>.*?<\/style>/mi, "")
    text.gsub!(/<script[^>]*>.*?<\/script>/mi, "")
    text.gsub!(/<head[^>]*>.*?<\/head>/mi, "")
    text.gsub!(/<br\s*\/?>/i, "\n")
    text.gsub!(/<\/(p|div|tr|li|h[1-6]|blockquote)>/i, "\n")
    text.gsub!(/<(p|div|tr|li|h[1-6]|blockquote)[^>]*>/i, "\n")
    text.gsub!(/<img[^>]*alt="([^"]*)"[^>]*>/i) { $1.present? ? "[#{$1}]" : "" }
    text.gsub!(/<a[^>]*href="([^"]*)"[^>]*>(.*?)<\/a>/im) { $2.strip }
    text.gsub!(/<[^>]+>/, "")

    # --- Decode entities ---
    text.gsub!("&nbsp;", " ")
    text.gsub!("&amp;", "&")
    text.gsub!("&lt;", "<")
    text.gsub!("&gt;", ">")
    text.gsub!("&quot;", '"')
    text.gsub!("&#39;", "'")
    text.gsub!(/&#(\d+);/) { [ $1.to_i ].pack("U") rescue "" }
    text.gsub!(/&\w+;/, "")

    # --- Decode quoted-printable artifacts ---
    text.gsub!(/=\r?\n/, "")
    text.gsub!(/=([0-9A-Fa-f]{2})/) { [ $1.hex ].pack("C") rescue "" }

    # --- Remove base64 blocks (inline attachments) ---
    text.gsub!(/[A-Za-z0-9+\/=]{76,}\n?/, "")

    # --- Process line by line ---
    lines = text.lines.map(&:rstrip)

    # Remove quoted replies
    quote_start = lines.index { |l| QUOTE_PATTERNS.any? { |p| l.match?(p) } }
    lines = lines[0...quote_start] if quote_start && quote_start > 0

    # Remove signature
    sig_start = lines.rindex { |l| SIGNATURE_PATTERNS.any? { |p| l.strip.match?(p) } }
    lines = lines[0...sig_start] if sig_start && sig_start > 0

    # Remove noise lines
    lines.reject! { |l| NOISE_PATTERNS.any? { |p| l.strip.match?(p) } }

    # --- Final cleanup ---
    text = lines.join("\n")
    text.gsub!(/[ \t]+/, " ")
    text.gsub!(/\n{3,}/, "\n\n")
    text.strip!

    text
  end

  # Extract just the email address from "Name <email>" format
  def self.extract_email_only(from_str)
    if from_str =~ /<([^>]+)>/
      $1
    else
      from_str
    end
  end
end
