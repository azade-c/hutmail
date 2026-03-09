module Vessel::Commanding
  extend ActiveSupport::Concern

  def parse_and_execute_commands(text)
    results = []
    in_commands = false
    in_messages = false
    current_recipient = nil
    current_body = []

    text.each_line do |line|
      stripped = line.strip

      if stripped.match?(/\A===CMD===\z/i)
        flush_outbound_message(current_recipient, current_body, results)
        in_commands = true
        in_messages = false
        next
      end

      if stripped.match?(/\A===END===\z/i)
        in_commands = false
        in_messages = false
        flush_outbound_message(current_recipient, current_body, results)
        next
      end

      if (match = stripped.match(/\A===MSG\s+(.+?)===\z/i))
        flush_outbound_message(current_recipient, current_body, results)
        in_messages = true
        in_commands = false
        current_recipient = match[1].strip
        current_body = []
        next
      end

      if in_commands
        execute_command(stripped, results) unless stripped.start_with?("#") || stripped.blank?
      elsif in_messages
        current_body << line
      end
    end

    flush_outbound_message(current_recipient, current_body, results)
    results
  end

  private
    def execute_command(line, results)
      tokens = line.split(/\s+/, 2)
      command = tokens[0].upcase
      args = tokens[1]&.strip

      case command
      when "DROP"      then execute_drop(args, results)
      when "GET"       then execute_get(args, results)
      when "SEND"      then execute_send(args, results)
      when "URGENT"    then execute_send(args, results, urgent: true)
      when "PAUSE"     then execute_pause(args, results)
      when "RESUME"    then execute_resume(results)
      when "STATUS"    then execute_status(results)
      when "WHITELIST" then execute_list(:whitelist, args, results)
      when "BLACKLIST" then execute_list(:blacklist, args, results)
      else
        results << { command: command, status: :unknown, message: "Unknown command: #{command}" }
      end
    end

    def execute_drop(args, results)
      if args&.upcase == "LAST"
        if (last_bundle = bundles.sent.recent.first)
          count = last_bundle.collected_messages.update_all(status: "pending", bundle_id: nil, sent_at: nil)
          results << { command: "DROP LAST", status: :ok, message: "#{count} messages returned to pending" }
        else
          results << { command: "DROP LAST", status: :error, message: "No sent bundle found" }
        end
      else
        messages = find_messages_by_wildcard(args)
        if messages.any?
          count = messages.update_all(status: "dropped")
          results << { command: "DROP #{args}", status: :ok, message: "#{count} messages dropped" }
        else
          results << { command: "DROP #{args}", status: :error, message: "No matching pending messages" }
        end
      end
    end

    def execute_get(args, results)
      messages = find_messages_by_wildcard(args)
      if messages.any?
        build_and_deliver_get_response(messages)
        results << { command: "GET #{args}", status: :ok, message: "#{messages.size} messages sent" }
      else
        results << { command: "GET #{args}", status: :error, message: "No matching pending messages" }
      end
    end

    def execute_send(args, results, urgent: false)
      if (match = args&.match(/\A(\S+)\s+"?(.+?)"?\z/))
        recipient = match[1]
        body = match[2]
        account = resolve_outbound_account(recipient)

        reply = vessel_replies.create!(
          mail_account: account,
          to_address: recipient,
          body: body,
          status: "pending"
        )

        if urgent
          VesselReply::DeliverJob.perform_now(reply)
        else
          VesselReply::DeliverJob.perform_later(reply)
        end

        label = urgent ? "URGENT" : "SEND"
        results << { command: "#{label} #{recipient}", status: :ok, message: "Reply queued" }
      else
        results << { command: "SEND", status: :error, message: "Invalid format. Use: SEND email@example.com \"message\"" }
      end
    end

    def execute_pause(args, results)
      # TODO: implement pause duration on vessel model
      results << { command: "PAUSE #{args}", status: :ok, message: "Aggregation paused" }
    end

    def execute_resume(results)
      results << { command: "RESUME", status: :ok, message: "Aggregation resumed" }
    end

    def execute_status(results)
      pending_count = CollectedMessage.pending
        .joins(:mail_account)
        .where(mail_accounts: { vessel_id: id })
        .count

      results << {
        command: "STATUS",
        status: :ok,
        message: "#{pending_count} pending messages, #{Bundle.format_size(budget_remaining)} budget remaining (7d)"
      }
    end

    def execute_list(type, args, results)
      # TODO: implement whitelist/blacklist on vessel model
      results << { command: "#{type.upcase} #{args}", status: :ok, message: "#{type} updated" }
    end

    def find_messages_by_wildcard(args)
      return CollectedMessage.none if args.blank?

      ids = args.split(/\s+/)
      all_messages = CollectedMessage.none

      ids.each do |id_str|
        messages = CollectedMessage.pending
          .joins(:mail_account)
          .where(mail_accounts: { vessel_id: self.id })

        messages = if id_str.match?(/\A\d+\z/)
          messages.where("collected_messages.hutmail_id LIKE ?", "%.#{id_str}")
        elsif id_str.match?(/\A[A-Z]{2}\z/)
          messages.where(mail_accounts: { short_code: id_str })
        else
          parsed = CollectedMessage.decompose_hutmail_id(id_str)
          messages = messages.where("DATE(collected_messages.date) = ?", parsed[:date]) if parsed[:date]
          messages = messages.where(mail_accounts: { short_code: parsed[:short_code] }) if parsed[:short_code]
          messages = messages.where("collected_messages.hutmail_id LIKE ?", "%.#{parsed[:sequence]}") if parsed[:sequence]
          messages
        end

        all_messages = all_messages.or(messages)
      end

      all_messages
    end

    def resolve_outbound_account(recipient)
      previous = CollectedMessage.where(from_address: recipient)
        .joins(:mail_account)
        .where(mail_accounts: { vessel_id: self.id })
        .first

      if previous
        previous.mail_account
      else
        mail_accounts.find_by(is_default: true) || mail_accounts.first
      end
    end

    def flush_outbound_message(recipient, body, results)
      return if recipient.blank? || body.blank?

      account = resolve_outbound_account(recipient)
      reply = vessel_replies.create!(
        mail_account: account,
        to_address: recipient,
        body: body.join.strip,
        status: "pending"
      )

      VesselReply::DeliverJob.perform_later(reply)
      results << { command: "MSG #{recipient}", status: :ok, message: "Reply queued" }
    end
end
