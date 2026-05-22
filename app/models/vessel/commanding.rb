module Vessel::Commanding
  extend ActiveSupport::Concern

  def parse_and_execute_commands(text)
    results = []
    in_commands = false
    in_messages = false
    current_block = nil # { kind: :msg | :resp, target: String, body: Array<String> }

    text.each_line do |line|
      stripped = line.strip

      if stripped.match?(/\A===CMD===\z/i)
        flush_outbound_block(current_block, results)
        in_commands = true
        in_messages = false
        current_block = nil
        next
      end

      if stripped.match?(/\A===END===\z/i)
        flush_outbound_block(current_block, results)
        in_commands = false
        in_messages = false
        current_block = nil
        next
      end

      if (match = stripped.match(/\A===MSG(?:\.([A-Za-z]{2}))?\s+(.+?)===\z/i))
        flush_outbound_block(current_block, results)
        in_messages = true
        in_commands = false
        current_block = { kind: :msg, short_code: match[1]&.upcase, target: match[2].strip, body: [] }
        next
      end

      if (match = stripped.match(/\A===REPLY\s+(.+?)===\z/i))
        flush_outbound_block(current_block, results)
        in_messages = true
        in_commands = false
        current_block = { kind: :reply, target: match[1].strip, body: [] }
        next
      end

      if in_commands
        execute_command(stripped, results) unless stripped.start_with?("#") || stripped.blank?
      elsif in_messages && current_block
        current_block[:body] << line
      end
    end

    flush_outbound_block(current_block, results)
    results
  end

  private
    def execute_command(line, results)
      tokens = line.split(/\s+/, 2)
      command = tokens[0].upcase
      args = tokens[1]&.strip

      base, scope = command.split(".", 2)

      case base
      when "GET"       then execute_get(args, results)
      when "SEND"      then execute_send(scope, args, results)
      when "URGENT"    then execute_send(scope, args, results, urgent: true)
      when "PAUSE"     then execute_pause(args, results)
      when "RESUME"    then execute_resume(results)
      when "STATUS"    then execute_status(results)
      when "WHITELIST" then execute_list(:whitelist, args, results)
      when "BLACKLIST" then execute_list(:blacklist, args, results)
      else
        results << { command: command, status: :unknown, message: "Unknown command: #{command}" }
      end
    end

    def execute_get(args, results)
      messages = find_messages_by_wildcard(args)

      if messages.any?
        dispatch_get_response(messages)
        results << { command: "GET #{args}", status: :ok, message: "#{messages.size} messages bundled" }
      else
        results << { command: "GET #{args}", status: :error, message: "No matching messages ready for bundling" }
      end
    end

    def execute_send(scope, args, results, urgent: false)
      label = urgent ? "URGENT" : "SEND"

      if scope.blank?
        results << { command: label, status: :error, message: "Invalid format. Use: #{label}.<ACCOUNT> <email> \"message\"" }
        return
      end

      unless (match = args&.match(/\A(\S+)\s+"?(.+?)"?\z/))
        results << { command: "#{label}.#{scope}", status: :error, message: "Invalid format. Use: #{label}.<ACCOUNT> <email> \"message\"" }
        return
      end

      short_code = scope.upcase
      recipient = match[1]
      body = match[2]
      account = mail_accounts.find_by(short_code: short_code)
      unless account
        results << { command: "#{label}.#{short_code}", status: :error, message: "Unknown account short_code: #{short_code}" }
        return
      end

      reply = vessel_replies.create!(
        mail_account: account,
        message_digest: nil,
        to_address: recipient,
        subject: "HutMail message",
        body: body,
        status: "pending"
      )

      if urgent
        reply.deliver_now
      else
        reply.deliver_later
      end

      results << { command: "#{label}.#{short_code} #{recipient}", status: :ok, message: "Message queued" }
    end

    def execute_pause(args, results)
      results << { command: "PAUSE #{args}", status: :ok, message: "Aggregation paused" }
    end

    def execute_resume(results)
      results << { command: "RESUME", status: :ok, message: "Aggregation resumed" }
    end

    def execute_status(results)
      bundleable_count = MessageDigest.bundleable
        .joins(:mail_account)
        .where(mail_accounts: { vessel_id: id })
        .count

      results << {
        command: "STATUS",
        status: :ok,
        message: "#{bundleable_count} messages ready for bundling, #{Bundle.format_size(budget_remaining)} budget remaining (7d)"
      }
    end

    def execute_list(type, args, results)
      results << { command: "#{type.upcase} #{args}", status: :ok, message: "#{type} updated" }
    end

    def find_messages_by_wildcard(args)
      return MessageDigest.none if args.blank?

      ids = args.split(/\s+/)
      all_messages = MessageDigest.none

      ids.each do |id_str|
        messages = MessageDigest.bundleable
          .joins(:mail_account)
          .where(mail_accounts: { vessel_id: id })

        messages = if id_str.match?(/\A\d+\z/)
          messages.where("message_digests.daily_sequence = ?", id_str.to_i)
        elsif id_str.match?(/\A[A-Z]{2}\z/)
          messages.where(mail_accounts: { short_code: id_str })
        else
          parsed = MessageDigest.decompose_hutmail_reference(id_str)
          messages = messages.where("DATE(message_digests.date) = ?", parsed[:date]) if parsed[:date]
          messages = messages.where(mail_accounts: { short_code: parsed[:short_code] }) if parsed[:short_code]
          messages = messages.where("message_digests.daily_sequence = ?", parsed[:sequence]) if parsed[:sequence]
          messages
        end

        all_messages = all_messages.or(messages)
      end

      all_messages
    end

    def subject_for_reply(original)
      subject = original.subject.to_s
      subject.match?(/\ARe:\s/i) ? subject : "Re: #{subject}"
    end

    def flush_outbound_block(block, results)
      return unless block
      return if block[:body].blank?
      return if block[:body].join.strip.empty?

      case block[:kind]
      when :reply then flush_outbound_reply(block[:target], block[:body], results)
      when :msg   then flush_outbound_message(block[:short_code], block[:target], block[:body], results)
      end
    end

    def flush_outbound_reply(hutmail_ref, body, results)
      original = resolve_message_by_hutmail_reference(hutmail_ref)

      unless original
        results << { command: "REPLY #{hutmail_ref}", status: :error, message: "Unknown hutmail_id: #{hutmail_ref}" }
        return
      end

      reply = vessel_replies.create!(
        mail_account: original.mail_account,
        message_digest: original,
        to_address: original.from_address,
        subject: subject_for_reply(original),
        body: body.join.strip,
        status: "pending"
      )

      reply.deliver_later
      results << { command: "REPLY #{hutmail_ref}", status: :ok, message: "Reply queued to #{original.from_address}" }
    end

    def flush_outbound_message(short_code, recipient, body, results)
      return if recipient.blank? || body.blank?

      if short_code.blank?
        results << { command: "MSG #{recipient}", status: :error, message: "Invalid format. Use: ===MSG.<ACCOUNT> <email>===" }
        return
      end

      account = mail_accounts.find_by(short_code: short_code)
      unless account
        results << { command: "MSG.#{short_code}", status: :error, message: "Unknown account short_code: #{short_code}" }
        return
      end

      vessel_replies.create!(
        mail_account: account,
        message_digest: nil,
        to_address: recipient,
        subject: "HutMail message",
        body: body.join.strip,
        status: "pending"
      ).deliver_later

      results << { command: "MSG.#{short_code} #{recipient}", status: :ok, message: "Message queued" }
    end

    def resolve_message_by_hutmail_reference(ref)
      parts = MessageDigest.decompose_hutmail_reference(ref)
      return nil if parts[:date].blank? || parts[:short_code].blank? || parts[:sequence].blank?

      MessageDigest
        .joins(:mail_account)
        .where(mail_accounts: { vessel_id: id, short_code: parts[:short_code] })
        .where("DATE(message_digests.date) = ?", parts[:date])
        .where(daily_sequence: parts[:sequence])
        .first
    end
end
