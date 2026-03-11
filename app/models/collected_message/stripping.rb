module CollectedMessage::Stripping
  extend ActiveSupport::Concern

  PLACEHOLDER_QUOTED = "[…message précédent…]"

  class_methods do
    QUOTED_REPLY_MARKERS = [
      /^>/,
      /^On .+ wrote:\s*$/i,
      /^Le .+ a écrit\s*:\s*$/i
    ].freeze

    def strip_mail(mail_message)
      text = extract_text(mail_message)
      return "" if text.blank?

      had_quoted = false

      text, removed = remove_french_reply_block(text)
      had_quoted ||= removed

      had_quoted ||= text.lines.any? { |l| QUOTED_REPLY_MARKERS.any? { |p| l.match?(p) } }
      text = remove_quoted_replies(text)

      text = remove_signatures(text)
      text = remove_noise(text)
      text = normalize_whitespace(text)

      text = append_placeholder(text, PLACEHOLDER_QUOTED) if had_quoted
      text = prepend_image_placeholders(text, mail_message)

      text
    end

    private

    def extract_text(mail_message)
      if mail_message.text_part
        mail_message.text_part.decoded.to_s
      elsif mail_message.html_part
        html_to_text(mail_message.html_part.decoded.to_s)
      elsif mail_message.content_type&.include?("text/html")
        html_to_text(mail_message.body.decoded.to_s)
      else
        mail_message.body.decoded.to_s
      end
    rescue => e
      Rails.logger.warn "CollectedMessage::Stripping: failed to extract text: #{e.message}"
      ""
    end

    def html_to_text(html)
      text = Html2Text.convert(html)
      text.gsub(/\[([^\]]+)\]\([^)]+\)/, '\1')
    end

    FRENCH_REPLY_BLOCK = /
      ^De\s*:\s*.+$\n
      (?:^(?:À|A|Cc|Objet|Date|Envoyé)\s*:\s*.+$\n)*
      (?:^(?:À|A|Cc|Objet|Date|Envoyé)\s*:\s*.+$)
      (?:\n|\z).*
    /xmi

    def remove_french_reply_block(text)
      if text.match?(FRENCH_REPLY_BLOCK)
        [ text.sub(FRENCH_REPLY_BLOCK, ""), true ]
      else
        [ text, false ]
      end
    end

    def remove_quoted_replies(text)
      text = EmailReplyParser.parse_reply(text)
      text = text.sub(/^Le .+? a écrit\s*:\s*\z/m, "")
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
      /^Envoyé à partir de .+$/i
    ].freeze

    DISCLAIMER_PATTERNS = [
      /^\*{3,}.*DISCLAIMER.*\*{3,}$/i,
      /^\*{3,}.*CONFIDENTIAL.*\*{3,}$/i,
      /^\*{3,}.*AVERTISSEMENT.*\*{3,}$/i,
      /^Ce message .+ confidentiel/i,
      /^This email .+ confidential/i,
      /^If you are not the intended recipient/i,
      /^Si vous n.?êtes pas le destinataire/i
    ].freeze

    NOISE_PATTERNS = [
      /^(un)?subscribe$/i,
      /^se désinscrire$/i,
      /^manage (your )?preferences$/i,
      /^gérer (vos )?préférences$/i,
      /^view (this )?(email )?in (your )?browser$/i,
      /^https?:\/\/\S+$/
    ].freeze

    def remove_signatures(text)
      lines = text.lines
      result = []
      lines.each do |line|
        break if SIGNATURE_PATTERNS.any? { |p| line.strip.match?(p) }
        result << line
      end
      result.join
    end

    def remove_noise(text)
      lines = text.lines
      disclaimer_index = lines.index { |l| DISCLAIMER_PATTERNS.any? { |p| l.strip.match?(p) } }
      lines = lines[0...disclaimer_index] if disclaimer_index
      lines.reject! { |l| NOISE_PATTERNS.any? { |p| l.strip.match?(p) } }
      lines.join
    end

    def normalize_whitespace(text)
      text
        .gsub(/[^\S\n]+/, " ")
        .gsub(/\n{3,}/, "\n\n")
        .strip
    end

    def append_placeholder(text, placeholder)
      text = text.strip
      return placeholder if text.empty?
      "#{text}\n\n#{placeholder}"
    end

    def prepend_image_placeholders(text, mail_message)
      images = collect_inline_images(mail_message)
      return text if images.empty?

      labels = images.map do |img|
        "[image : #{img[:name]} (#{Bundle.format_size(img[:size])})]"
      end

      prefix = labels.join("\n")
      text.empty? ? prefix : "#{prefix}\n\n#{text}"
    end

    def collect_inline_images(mail_message)
      return [] unless mail_message.multipart?

      mail_message.parts.filter_map do |part|
        next unless part.content_type&.start_with?("image/")
        next unless part.content_disposition&.include?("inline")

        name = part.filename.presence || "image"
        size = part.body.decoded.bytesize rescue 0

        { name:, size: }
      end
    end
  end
end
