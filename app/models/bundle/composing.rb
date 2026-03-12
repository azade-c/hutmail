module Bundle::Composing
  extend ActiveSupport::Concern

  class_methods do
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

  def compose!(included_messages, remaining_messages)
    compose_text(included_messages, remaining_messages)
    save!
    included_messages.each { |msg| bundle_items.create!(message_digest: msg) }
  end

  def compose_text(included_messages, remaining_messages)
    screener_text = compose_screener(remaining_messages, vessel.screener_budget)

    timestamp = Time.current.strftime("%d%b %H:%M").downcase
    lines = []
    lines << "=== HUTMAIL #{timestamp} ==="
    lines << ""

    included_messages.group_by(&:mail_account).each do |account, messages|
      lines << "==[ #{account.short_code} — #{account.name} (#{account.imap_username}) ]=="
      lines << ""
      messages.sort_by(&:id).each do |msg|
        lines << msg.to_radio_text
        lines << ""
      end
    end

    lines << screener_text if screener_text.present?
    lines << "=== END ==="

    self.bundle_text = lines.join("\n")
    self.total_raw_size = included_messages.sum(&:raw_size)
    self.total_stripped_size = included_messages.sum(&:stripped_size)
    self.messages_count = included_messages.size
    self.remaining_count = remaining_messages.size

    self
  end

  private
    def compose_screener(remaining, budget)
      return nil if remaining.empty?

      total_size = remaining.sum(&:stripped_size)
      lines = []
      lines << "=== SCREENER (#{remaining.size} messages, #{self.class.format_size(total_size)}) ==="

      consumed = lines.first.bytesize
      truncated = 0

      remaining.each do |msg|
        line = msg.to_screener_line

        if consumed + line.bytesize + 1 > budget && budget > 0
          truncated = remaining.size - lines.size + 1
          break
        end

        lines << line
        consumed += line.bytesize + 1
      end

      lines << "... and #{truncated} more messages ready for bundling" if truncated > 0
      lines << "GET <id> to download a specific message"
      lines.join("\n")
    end
end
