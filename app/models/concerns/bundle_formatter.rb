class BundleFormatter
  HEADER_SEPARATOR = "=" * 40

  class << self
    def format(included, remaining, screener_text, user)
      timestamp = Time.current.strftime("%d%b %H:%M").downcase
      lines = []
      lines << "=== HUTMAIL #{timestamp} ==="
      lines << ""

      # Group by mail account
      included.group_by(&:mail_account).each do |account, messages|
        lines << "==[ #{account.short_code} — #{account.name} (#{account.imap_username}) ]=="
        lines << ""

        messages.each do |msg|
          lines << format_message(msg)
          lines << ""
        end
      end

      if screener_text.present?
        lines << screener_text
      end

      lines << "=== END ==="
      lines.join("\n")
    end

    def format_message(msg)
      header = format_header(msg)
      attachments = format_attachments(msg.attachments_metadata)

      parts = [ header ]
      parts << attachments if attachments
      parts << msg.stripped_body if msg.stripped_body.present?
      parts.join("\n")
    end

    def format_header(msg)
      date_str = msg.date&.strftime("%d%b %H:%M")&.downcase || "?"
      from = msg.from_name.presence || msg.from_address
      recipients = format_recipients(msg)

      header = "[#{msg.hutmail_id}] From: #{from}"
      header += " #{recipients}" if recipients.present?
      header += " | #{msg.subject}" if msg.subject.present?
      header += " | #{date_str}"
      header
    end

    def format_recipients(msg)
      return nil if msg.to_address.blank?

      to_list = msg.to_address.split(",").map(&:strip)
      account_email = msg.mail_account.imap_username

      # Remove the monitored mailbox itself
      others = to_list.reject { |a| a.downcase == account_email&.downcase }
      return nil if others.empty?

      parts = []

      if others.size == 1
        parts << "(→ #{abbreviate_email(others.first)})"
      elsif others.size > 1
        parts << "(+#{others.size})"
      end

      # TODO: AC 07mar26 add CC count when we store CC data
      parts.join(" ")
    end

    def format_screener(remaining, budget)
      return nil if remaining.empty?

      total_size = remaining.sum(&:stripped_size)
      lines = []
      lines << "=== SCREENER (#{remaining.size} messages, #{format_size(total_size)}) ==="

      consumed = lines.first.bytesize
      truncated = 0

      remaining.each do |msg|
        from = msg.from_name.presence || msg.from_address
        line = "[#{msg.hutmail_id}] #{from} | \"#{msg.subject}\" | #{format_size(msg.stripped_size)}"

        if consumed + line.bytesize + 1 > budget && budget > 0
          truncated = remaining.size - lines.size + 1
          break
        end

        lines << line
        consumed += line.bytesize + 1
      end

      if truncated > 0
        lines << "... and #{truncated} more messages pending"
      end

      lines << "GET <id> to download a specific message"
      lines.join("\n")
    end

    def format_attachments(metadata)
      return nil if metadata.blank?

      items = metadata.map do |att|
        "#{att['name'] || att[:name]} (#{format_size(att['size'] || att[:size])})"
      end

      "📎 #{items.join(', ')}"
    end

    def format_size(bytes)
      if bytes >= 1024 * 1024
        "%.1f MB" % (bytes / (1024.0 * 1024))
      elsif bytes >= 1024
        "%.1f KB" % (bytes / 1024.0)
      else
        "#{bytes} B"
      end
    end
  end
end
