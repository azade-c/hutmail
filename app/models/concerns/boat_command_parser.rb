class BoatCommandParser
  attr_reader :vessel, :results

  def initialize(vessel)
    @vessel = vessel
    @results = []
  end

  def parse_and_execute(text)
    in_commands = false
    in_messages = false
    current_recipient = nil
    current_body = []

    text.each_line do |line|
      stripped = line.strip

      if stripped.match?(/\A===CMD===\z/i)
        flush_message(current_recipient, current_body)
        in_commands = true
        in_messages = false
        next
      end

      if stripped.match?(/\A===END===\z/i)
        in_commands = false
        in_messages = false
        flush_message(current_recipient, current_body)
        next
      end

      if (match = stripped.match(/\A===MSG\s+(.+?)===\z/i))
        flush_message(current_recipient, current_body)
        in_messages = true
        in_commands = false
        current_recipient = match[1].strip
        current_body = []
        next
      end

      if in_commands
        execute_command(stripped) unless stripped.start_with?("#") || stripped.blank?
      elsif in_messages
        current_body << line
      end
    end

    flush_message(current_recipient, current_body)
    results
  end

  private

  def execute_command(line)
    tokens = line.split(/\s+/, 2)
    command = tokens[0].upcase
    args = tokens[1]&.strip

    case command
    when "DROP" then handle_drop(args)
    when "GET" then handle_get(args)
    when "SEND" then handle_send(args)
    when "URGENT" then handle_send(args, urgent: true)
    when "PAUSE" then handle_pause(args)
    when "RESUME" then handle_resume
    when "STATUS" then handle_status
    when "WHITELIST" then handle_list(:whitelist, args)
    when "BLACKLIST" then handle_list(:blacklist, args)
    else
      results << { command: command, status: :unknown, message: "Unknown command: #{command}" }
    end
  end

  def handle_drop(args)
    if args&.upcase == "LAST"
      last_bundle = vessel.bundles.sent.recent.first
      if last_bundle
        count = last_bundle.collected_messages.update_all(status: "pending", bundle_id: nil, sent_at: nil)
        results << { command: "DROP LAST", status: :ok, message: "#{count} messages returned to pending" }
      else
        results << { command: "DROP LAST", status: :error, message: "No sent bundle found" }
      end
    else
      drop_by_wildcard(args)
    end
  end

  def handle_get(args)
    messages = find_by_wildcard(args)
    if messages.any?
      # Build a mini-bundle with these messages
      builder = GetResponseBuilder.new(vessel, messages)
      builder.build_and_deliver
      results << { command: "GET #{args}", status: :ok, message: "#{messages.size} messages sent" }
    else
      results << { command: "GET #{args}", status: :error, message: "No matching pending messages" }
    end
  end

  def handle_send(args, urgent: false)
    match = args&.match(/\A(\S+)\s+"?(.+?)"?\z/)
    if match
      recipient = match[1]
      body = match[2]
      account = resolve_smtp_account(recipient)

      reply = vessel.boat_replies.create!(
        mail_account: account,
        to_address: recipient,
        body: body,
        status: "pending"
      )

      if urgent
        BoatReply::DeliverJob.perform_now(reply)
      else
        BoatReply::DeliverJob.perform_later(reply)
      end

      label = urgent ? "URGENT" : "SEND"
      results << { command: "#{label} #{recipient}", status: :ok, message: "Reply queued" }
    else
      results << { command: "SEND", status: :error, message: "Invalid format. Use: SEND email@example.com \"message\"" }
    end
  end

  def handle_pause(args)
    # TODO: AC 07mar26 implement pause duration on vessel model
    results << { command: "PAUSE #{args}", status: :ok, message: "Aggregation paused" }
  end

  def handle_resume
    results << { command: "RESUME", status: :ok, message: "Aggregation resumed" }
  end

  def handle_status
    pending_count = vessel.mail_accounts.joins(:collected_messages).where(collected_messages: { status: "pending" }).count
    budget_remaining = vessel.budget_remaining
    results << {
      command: "STATUS",
      status: :ok,
      message: "#{pending_count} pending messages, #{BundleFormatter.format_size(budget_remaining)} budget remaining (7d)"
    }
  end

  def handle_list(type, args)
    # TODO: AC 07mar26 implement whitelist/blacklist on vessel model
    results << { command: "#{type.upcase} #{args}", status: :ok, message: "#{type} updated" }
  end

  def drop_by_wildcard(args)
    messages = find_by_wildcard(args)
    if messages.any?
      count = messages.update_all(status: "dropped")
      results << { command: "DROP #{args}", status: :ok, message: "#{count} messages dropped" }
    else
      results << { command: "DROP #{args}", status: :error, message: "No matching pending messages" }
    end
  end

  def find_by_wildcard(args)
    return CollectedMessage.none if args.blank?

    # Multiple space-separated identifiers
    ids = args.split(/\s+/)
    all_messages = CollectedMessage.none

    ids.each do |id|
      parsed = HutmailIdGenerator.parse(id)
      messages = CollectedMessage.pending
        .joins(:mail_account)
        .where(mail_accounts: { vessel_id: vessel.id })

      if parsed[:date]
        messages = messages.where("DATE(collected_messages.date) = ?", parsed[:date])
      end

      if parsed[:short_code]
        messages = messages.where(mail_accounts: { short_code: parsed[:short_code] })
      end

      if parsed[:sequence]
        # Filter by sequence number in hutmail_id (last segment after .)
        messages = messages.where("collected_messages.hutmail_id LIKE ?", "%.#{parsed[:sequence]}")
      end

      all_messages = all_messages.or(messages)
    end

    all_messages
  end

  def resolve_smtp_account(recipient)
    # Check if this recipient has previously written to us
    previous = CollectedMessage.where(from_address: recipient)
      .joins(:mail_account)
      .where(mail_accounts: { vessel_id: vessel.id })
      .first

    if previous
      previous.mail_account
    else
      vessel.mail_accounts.find_by(is_default: true) || vessel.mail_accounts.first
    end
  end

  def flush_message(recipient, body)
    return if recipient.blank? || body.blank?

    account = resolve_smtp_account(recipient)
    reply = vessel.boat_replies.create!(
      mail_account: account,
      to_address: recipient,
      body: body.join.strip,
      status: "pending"
    )

    BoatReply::DeliverJob.perform_later(reply)
    results << { command: "MSG #{recipient}", status: :ok, message: "Reply queued" }
  end
end
