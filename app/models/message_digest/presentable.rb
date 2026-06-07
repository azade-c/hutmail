module MessageDigest::Presentable
  extend ActiveSupport::Concern

  STATUS_LABELS = {
    "collected" => "collecté",
    "no_longer_collectable" => "hors collecte",
    "bundled" => "dépêché",
    "requeued" => "à regrouper"
  }.freeze

  def status_label
    STATUS_LABELS.fetch(status, status)
  end

  def format_sender
    if from_name.present?
      "#{from_name} <#{from_address}>"
    else
      from_address
    end
  end

  def to_radio_header
    date_str = date&.strftime("%d%b %H:%M")&.downcase || "?"
    recipients = format_recipients

    header = "[#{hutmail_reference}] From: #{format_sender}"
    header += " #{recipients}" if recipients.present?
    header += " | #{subject}" if subject.present?
    header += " | #{date_str}"
    header
  end

  def to_radio_text(char_limit: nil)
    parts = [ to_radio_header ]
    parts << truncated_body(char_limit) if stripped_body.present?
    parts << format_attachments if displayed_attachments.present?
    parts.join("\n")
  end

  def to_screener_line
    %(#{"[#{hutmail_reference}]"} #{format_sender} | "#{subject}" | #{Bundle.format_size(stripped_size)})
  end

  private
    def truncated_body(char_limit)
      body = stripped_body
      return body if char_limit.blank? || body.length <= char_limit

      dropped = body.length - char_limit
      "#{body[0, char_limit]}\n// message tronqué, restent #{dropped} caractères //"
    end

    def format_recipients
      return nil if to_address.blank?

      to_list = to_address.split(",").map(&:strip)
      account_email = mail_account.imap_username
      others = to_list.reject { |address| address.downcase == account_email&.downcase }
      return nil if others.empty?

      if others.size == 1
        local = others.first.split("@").first
        "(→ #{local})"
      else
        "(+#{others.size})"
      end
    end

    def format_attachments
      items = displayed_attachments.map do |attachment|
        "#{attachment_name(attachment)} (#{Bundle.format_size(attachment_size(attachment))})"
      end
      "📎 #{items.join(', ')}"
    end

    def displayed_attachments
      Array(attachments_metadata).reject do |attachment|
        embedded_attachment?(attachment)
      end
    end

    def embedded_attachment?(attachment)
      inline_placeholder_present?(attachment_name(attachment), attachment_size(attachment))
    end

    def inline_placeholder_present?(name, size)
      formatted = Bundle.format_size(size)
      stripped_body.to_s.include?("[image : #{name} (#{formatted})]") ||
        stripped_body.to_s.include?("[fichier : #{name} (#{formatted})]")
    end

    def attachment_name(attachment)
      attachment["name"] || attachment[:name]
    end

    def attachment_size(attachment)
      attachment["size"] || attachment[:size]
    end
end
