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

  def compose!(included_messages, remaining_messages, truncate: true)
    compose_text(included_messages, remaining_messages, truncate: truncate)
    save!
    included_messages.each { |msg| bundle_items.create!(message_digest: msg) }
    attach_pending_command_responses
    log_step "Composition (#{included_messages.size} messages, #{self.class.format_size(dispatch_size || 0)} transmis)"
  end

  def compose_text(included_messages, remaining_messages, truncate: true)
    char_limit = truncate ? vessel.message_char_limit : nil
    screener_text = compose_screener(remaining_messages, vessel.screener_budget)
    pending_responses = vessel.command_responses.pending_for_bundle.to_a

    timestamp = Time.current.strftime("%d%b %H:%M").downcase
    lines = []
    lines << "=== HUTMAIL #{timestamp} ==="
    lines << ""

    pending_responses.each do |cr|
      lines << "==[ \u2709 #{cr.command} response ]=="
      lines << cr.response_text
      lines << ""
    end

    @pending_command_responses = pending_responses

    included_messages.group_by(&:mail_account).each do |account, messages|
      lines << "==[ #{account.short_code} — #{account.name} (#{account.imap_username}) ]=="
      lines << ""
      messages.sort_by(&:imap_uid).each_with_index do |msg, index|
        lines << msg.to_radio_text(char_limit: char_limit)
        lines << ""
        lines << "==== %%%%%%%%%% ====" unless index == messages.size - 1
        lines << "" unless index == messages.size - 1
      end
    end

    lines << screener_text if screener_text.present?

    self.dispatch_size = dispatch_size_with_budget_footer(lines)
    lines << budget_footer(dispatch_size)
    lines << "=== END ==="

    self.bundle_text = lines.join("\n")
    self.total_raw_size = included_messages.sum(&:raw_size)
    self.total_stripped_size = included_messages.sum(&:stripped_size)
    self.messages_count = included_messages.size
    self.remaining_count = remaining_messages.size

    self
  end

  private
    def dispatch_size_with_budget_footer(lines)
      previous_size = nil
      current_size = 0

      until current_size == previous_size
        previous_size = current_size
        current_size = (lines.join("\n") + "\n#{budget_footer(previous_size)}\n=== END ===").bytesize
      end

      current_size
    end

    def budget_footer(this_dispatch_size)
      remaining_after = [ vessel.budget_remaining - this_dispatch_size, 0 ].max
      "Restent #{self.class.format_size(remaining_after)} / #{self.class.format_size(vessel.budget_total)} (7j glissants)"
    end

    def attach_pending_command_responses
      Array(@pending_command_responses).each do |cr|
        cr.update!(bundle: self, status: "included")
      end
    end

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
