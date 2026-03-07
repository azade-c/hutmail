module MessageStripper
  extend self

  def strip(mail_message)
    text = extract_text(mail_message)
    return "" if text.blank?

    text = remove_quoted_replies(text)
    text = remove_signatures(text)
    text = remove_noise(text)
    normalize_whitespace(text)
  end

  private

  def extract_text(mail_message)
    if mail_message.text_part
      mail_message.text_part.decoded.to_s
    elsif mail_message.html_part
      html_to_text(mail_message.html_part.decoded.to_s)
    elsif mail_message.content_type&.include?("text/html")
      html_to_text(mail_message.body.decoded.to_s)
    elsif mail_message.content_type&.include?("text/plain")
      mail_message.body.decoded.to_s
    else
      ""
    end
  rescue => e
    Rails.logger.warn "MessageStripper: failed to extract text: #{e.message}"
    ""
  end

  def html_to_text(html)
    text = Html2Text.convert(html)
    # html2text produces [text](url) links — strip URLs, keep text
    text.gsub(/\[([^\]]+)\]\([^)]+\)/, '\1')
  end

  def remove_quoted_replies(text)
    # Use GitHub's email_reply_parser for standard patterns
    text = EmailReplyParser.parse_reply(text)

    # French patterns not covered by email_reply_parser
    text = text.sub(/^Le .+? a écrit\s*:\s*\z/m, "")
    text = text.sub(/^De\s*:.+?\z/m, "")
    text = text.sub(/^Envoyé\s*:.+?\z/m, "")
    text = text.sub(/^-{2,}\s*Message transféré\s*-{2,}.*\z/m, "")
    text = text.sub(/^-{2,}\s*Forwarded message\s*-{2,}.*\z/m, "")

    text
  end

  SIGNATURE_PATTERNS = [
    /^Sent from my .+$/i,
    /^Envoyé de mon .+$/i,
    /^Envoyé depuis .+$/i,
    /^Get Outlook for .+$/i,
    /^Télécharger Outlook .+$/i,
    /^Obtenir Outlook .+$/i,
    /^Sent from Mail for .+$/i,
    /^Envoyé à partir de .+$/i,
  ].freeze

  DISCLAIMER_PATTERNS = [
    /^\*{3,}.*DISCLAIMER.*\*{3,}$/i,
    /^\*{3,}.*CONFIDENTIAL.*\*{3,}$/i,
    /^\*{3,}.*AVERTISSEMENT.*\*{3,}$/i,
    /^Ce message .+ confidentiel/i,
    /^This email .+ confidential/i,
    /^If you are not the intended recipient/i,
    /^Si vous n.?êtes pas le destinataire/i,
  ].freeze

  NOISE_PATTERNS = [
    /^(un)?subscribe$/i,
    /^se désinscrire$/i,
    /^manage (your )?preferences$/i,
    /^gérer (vos )?préférences$/i,
    /^view (this )?(email )?in (your )?browser$/i,
    /^https?:\/\/\S+$/,  # lines containing only a URL
  ].freeze

  def remove_signatures(text)
    lines = text.lines
    result = []

    lines.each do |line|
      stripped_line = line.strip
      break if SIGNATURE_PATTERNS.any? { |p| stripped_line.match?(p) }
      result << line
    end

    result.join
  end

  def remove_noise(text)
    lines = text.lines

    # Remove disclaimer blocks (from first match to end)
    disclaimer_index = lines.index { |l| DISCLAIMER_PATTERNS.any? { |p| l.strip.match?(p) } }
    lines = lines[0...disclaimer_index] if disclaimer_index

    # Remove individual noise lines
    lines.reject! { |l| NOISE_PATTERNS.any? { |p| l.strip.match?(p) } }

    lines.join
  end

  def normalize_whitespace(text)
    text
      .gsub(/[^\S\n]+/, " ")         # collapse horizontal whitespace
      .gsub(/\n{3,}/, "\n\n")        # max 1 blank line
      .strip
  end
end
