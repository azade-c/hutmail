module CollectedMessage::Stripping
  extend ActiveSupport::Concern

  PLACEHOLDER_QUOTED = "[…message précédent…]"

  class_methods do
    QUOTED_REPLY_MARKERS = [
      /^\s*>/,
      /^\s*On .+ wrote:\s*$/i,
      /^\s*Le .+ a écrit\s*:\s*$/i
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
      text = place_inline_image_placeholders(text, mail_message)

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

    FRENCH_REPLY_HEADERS = /\A(?:De|À|A|Cc|Objet|Date|Envoyé)\s*:\s*.+\z/i

    def remove_french_reply_block(text)
      lines = text.lines
      reply_start = find_french_reply_start(lines)

      if reply_start
        [ lines[0...reply_start].join, true ]
      else
        [ text, false ]
      end
    end

    def find_french_reply_start(lines)
      lines.each_index do |index|
        next unless french_reply_origin?(lines[index])
        next unless french_reply_header_count(lines, index) >= 2

        return index
      end

      nil
    end

    def french_reply_origin?(line)
      normalize_reply_line(line).match?(/\ADe\s*:\s*.+\z/i)
    end

    def french_reply_header_count(lines, start_index)
      count = 0

      lines[start_index..].each do |line|
        normalized_line = normalize_reply_line(line)

        if normalized_line.empty?
          next
        elsif normalized_line.match?(FRENCH_REPLY_HEADERS)
          count += 1
        else
          break
        end
      end

      count
    end

    def normalize_reply_line(line)
      line.to_s.tr("\u00A0", " ").sub(/\A(?:>\s*)+/, "").strip
    end

    def remove_quoted_replies(text)
      text = EmailReplyParser.parse_reply(text)
      text = text.sub(/^\s*Le .+? a écrit\s*:\s*\z/m, "")
      text = text.sub(/^\s*-{2,}\s*Message transféré\s*-{2,}.*\z/m, "")
      text = text.sub(/^\s*-{2,}\s*Forwarded message\s*-{2,}.*\z/m, "")
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

    def place_inline_image_placeholders(text, mail_message)
      images = collect_inline_images(mail_message)
      return text if images.empty?

      positioned_text = position_image_placeholders_from_html(text, mail_message, images)
      return positioned_text if positioned_text

      prepend_image_placeholders(text, images)
    end

    def position_image_placeholders_from_html(text, mail_message, images)
      html = extract_html(mail_message)
      return if html.blank?

      html_text = html_to_text(replace_inline_images_in_html(html, images))
      html_lines = normalize_whitespace(html_text).lines(chomp: true)
      text_lines = text.lines(chomp: true)
      inserted = 0

      html_lines.each_with_index do |line, index|
        next unless image_placeholder?(line)
        next if text_lines.include?(line)

        insert_at = find_placeholder_position(text_lines, html_lines, index)
        next unless insert_at

        text_lines.insert(insert_at, line, "")
        inserted += 1
      end

      if inserted.positive?
        normalize_whitespace(text_lines.join("\n"))
      end
    end

    def replace_inline_images_in_html(html, images)
      html.gsub(/<img\b[^>]*src=(['"])cid:([^'"]+)\1[^>]*>/i) do |tag|
        cid = normalize_content_id(Regexp.last_match(2))
        image = images.find { |img| img[:cid] == cid }

        image ? image_placeholder(image) : tag
      end
    end

    def find_placeholder_position(text_lines, html_lines, placeholder_index)
      before_anchor = html_lines[0...placeholder_index].reverse.find(&:present?)
      after_anchor = html_lines[(placeholder_index + 1)..].to_a.find(&:present?)

      if before_anchor
        before_index = find_anchor_line(text_lines, before_anchor)
        return insertion_index_after(text_lines, before_index) if before_index
      end

      if after_anchor
        after_index = find_anchor_line(text_lines, after_anchor)
        after_index if after_index
      end
    end

    def find_anchor_line(lines, anchor)
      normalized_anchor = comparable_line(anchor)

      lines.index do |line|
        comparable_line(line) == normalized_anchor
      end
    end

    def insertion_index_after(lines, index)
      insert_at = index + 1
      insert_at += 1 while insert_at < lines.length && lines[insert_at].blank?
      insert_at
    end

    def comparable_line(line)
      line.to_s.tr("\u00A0", " ").squish
    end

    def prepend_image_placeholders(text, images)
      prefix = images.map { |img| image_placeholder(img) }.join("\n")
      text.empty? ? prefix : "#{prefix}\n\n#{text}"
    end

    def image_placeholder(image)
      "[image : #{image[:name]} (#{Bundle.format_size(image[:size])})]"
    end

    def image_placeholder?(line)
      line.start_with?("[image : ")
    end

    def extract_html(mail_message)
      if mail_message.html_part
        mail_message.html_part.decoded.to_s
      elsif mail_message.content_type&.include?("text/html")
        mail_message.body.decoded.to_s
      end
    end

    def collect_inline_images(mail_message)
      return [] unless mail_message.multipart?

      Array(mail_message.all_parts).filter_map do |part|
        next unless inline_image?(part)

        name = part.filename.presence || "image"
        size = part.body.decoded.bytesize rescue 0
        cid = normalize_content_id(part.content_id)

        { name:, size:, cid: }
      end.uniq
    end

    def normalize_content_id(content_id)
      content_id.to_s.delete_prefix("<").delete_suffix(">")
    end

    def inline_image?(part)
      part.mime_type&.start_with?("image/") &&
        (part.inline? || part.content_disposition&.include?("inline") || part.content_id.present?)
    end
  end
end
