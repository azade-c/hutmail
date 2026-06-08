module Vessel::Commanding
  extend ActiveSupport::Concern

  SUBJECT_REPLY_PREFIX = /\A(?:re|fw|fwd|tr)\s*:\s*/i
  SUBJECT_ALLOWED_COMMANDS = %w[STATUS PING HELP GET URGENT].freeze
  RESPONDING_COMMANDS = %w[STATUS PING HELP].freeze

  def parse_and_execute_subject(subject)
    return [] if subject.blank?

    cleaned = subject.to_s.dup
    cleaned.sub!(SUBJECT_REPLY_PREFIX, "") while cleaned.match?(SUBJECT_REPLY_PREFIX)
    cleaned.strip!
    return [] if cleaned.empty?

    verb = cleaned.split(/[\s.]/, 2).first.to_s.upcase
    return [] unless SUBJECT_ALLOWED_COMMANDS.include?(verb)

    results = []
    execute_command(cleaned, results, source: "subject")
    results
  end

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

      if in_commands && current_block&.fetch(:kind) == :send
        if command_line?(stripped)
          flush_outbound_block(current_block, results)
          current_block = nil
        else
          current_block[:body] << line
          next
        end
      end

      if in_commands
        next if stripped.start_with?("#") || stripped.blank?

        if (block = open_send_block(stripped))
          flush_outbound_block(current_block, results)
          current_block = block
          next
        end

        execute_command(stripped, results, source: "body")
      elsif in_messages && current_block
        current_block[:body] << line
      end
    end

    flush_outbound_block(current_block, results)
    results
  end

  private
    SEND_COMMAND = /\A(SEND|URGENT)(?:\.([A-Za-z0-9]+))?\s+(\S+)\s*\z/i
    KNOWN_COMMAND_VERBS = %w[GET SEND URGENT PAUSE RESUME STATUS PING HELP WHITELIST BLACKLIST].freeze

    def open_send_block(line)
      return unless (match = line.match(SEND_COMMAND))

      {
        kind: :send,
        urgent: match[1].upcase == "URGENT",
        short_code: match[2]&.upcase,
        target: match[3].strip,
        body: []
      }
    end

    def command_line?(line)
      verb = line.split(/[\s.]/, 2).first.to_s.upcase
      KNOWN_COMMAND_VERBS.include?(verb)
    end
    def execute_command(line, results, source: "body")
      tokens = line.split(/\s+/, 2)
      command = tokens[0].upcase
      args = tokens[1]&.strip

      base, scope = command.split(".", 2)

      case base
      when "GET"       then execute_get(args, results, source: source)
      when "SEND"      then execute_send(scope, args, results, source: source)
      when "URGENT"    then execute_send(scope, args, results, source: source, urgent: true)
      when "PAUSE"     then execute_pause(args, results)
      when "RESUME"    then execute_resume(results)
      when "STATUS"    then execute_status(results, source: source)
      when "PING"      then execute_ping(results, source: source)
      when "HELP"      then execute_help(results, source: source)
      when "WHITELIST" then execute_list(:whitelist, args, results)
      when "BLACKLIST" then execute_list(:blacklist, args, results)
      else
        report_error(results, source: source, command: command, status: :unknown,
          message: "Unknown command: #{command}", response: "unknown command \"#{command}\"")
      end
    end

    def execute_get(args, results, source: "body")
      messages = find_messages_by_wildcard(args)

      if messages.any?
        dispatch_get_response(messages)
        results << { command: "GET #{args}", status: :ok, message: "#{messages.size} messages bundled" }
      else
        report_error(results, source: source, command: "GET #{args}",
          message: "No matching messages found")
      end
    end

    def execute_send(scope, args, results, source: "body", urgent: false)
      label = urgent ? "URGENT" : "SEND"

      if scope.blank?
        report_error(results, source: source, command: label,
          message: "Invalid format. Use: #{label}.<ACCOUNT> <email> \"message\"")
        return
      end

      unless (match = args&.match(/\A(\S+)\s+"?(.+?)"?\z/))
        report_error(results, source: source, command: "#{label}.#{scope}",
          message: "Invalid format. Use: #{label}.<ACCOUNT> <email> \"message\"")
        return
      end

      short_code = scope.upcase
      recipient = match[1]
      body = match[2]
      account = mail_accounts.find_by(short_code: short_code)
      unless account
        report_error(results, source: source, command: "#{label}.#{short_code}",
          message: "Unknown account short_code: #{short_code}")
        return
      end

      reply = vessel_replies.create!(
        mail_account: account,
        message_digest: nil,
        to_address: recipient,
        subject: "Hutmail message",
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

    def execute_status(results, source: "body")
      bundleable_count = MessageDigest.bundleable
        .joins(:mail_account)
        .where(mail_accounts: { vessel_id: id })
        .count

      results << {
        command: "STATUS",
        status: :ok,
        message: "#{bundleable_count} messages ready for bundling, #{Bundle.format_size(budget_remaining)} budget remaining (7d)"
      }
      enqueue_response(source: source, command: "STATUS", text: status_response_text(bundleable_count))
    end

    def execute_ping(results, source: "body")
      text = "PONG #{Time.current.utc.strftime('%Y-%m-%dT%H:%MZ')} hutmail"
      results << { command: "PING", status: :ok, message: text }
      enqueue_response(source: source, command: "PING", text: text)
    end

    def execute_help(results, source: "body")
      results << { command: "HELP", status: :ok, message: "Command list returned" }
      enqueue_response(source: source, command: "HELP", text: help_response_text)
    end

    def status_response_text(bundleable_count)
      next_at = next_dispatch_at&.utc&.strftime("%d%b %H:%MZ")&.downcase
      last_at = last_dispatched_at&.utc&.strftime("%d%b %H:%MZ")&.downcase
      lines = []
      lines << "STATUS hutmail"
      lines << "ready: #{bundleable_count} messages"
      lines << "budget: #{Bundle.format_size(budget_remaining)} remaining (7d)"
      lines << "last dispatch: #{last_at || '-'}"
      lines << "next dispatch: #{next_at || 'manual'} (#{dispatch_cadence})"
      lines.join("\n")
    end

    def help_response_text
      <<~TXT.strip
        HUTMAIL commands
        Subject (answered immediately): STATUS | PING | HELP | GET <ref> | URGENT.<ACCT> <email> "msg"
        Body (in ===CMD===...===END===): all of the above + SEND.<ACCT> <email> "msg" | PAUSE | RESUME
        SEND/URGENT also accept the message on the lines below: SEND.<ACCT> <email> then text until the next command or ===END===
        Messages: ===MSG.<ACCT> <email>=== body ===END===  or  ===REPLY <ref>=== body ===END===
        Custom subject (SEND/URGENT/MSG): start the body with  OBJET your subject /OBJET  then the message below
      TXT
    end

    def enqueue_response(source:, command:, text:)
      response = command_responses.create!(
        source: source,
        command: command,
        response_text: text,
        status: "pending"
      )
      response.deliver_later if source == "subject"
      response
    end

    def report_error(results, source:, command:, message:, status: :error, response: nil)
      results << { command: command, status: status, message: message }
      enqueue_response(source: source, command: command, text: "ERR #{command}: #{response || message}")
    end

    def execute_list(type, args, results)
      results << { command: "#{type.upcase} #{args}", status: :ok, message: "#{type} updated" }
    end

    def find_messages_by_wildcard(args)
      return MessageDigest.none if args.blank?

      ids = args.split(/\s+/)
      all_messages = MessageDigest.none

      ids.each do |id_str|
        scope = MessageDigest
          .joins(:mail_account)
          .where(mail_accounts: { vessel_id: id })

        messages = if id_str.match?(/\A\d+\z/)
          scope.bundleable.where("message_digests.daily_sequence = ?", id_str.to_i)
        elsif id_str.match?(/\A[A-Z]{2}\z/)
          scope.bundleable.where(mail_accounts: { short_code: id_str })
        else
          # A precise reference (date.code.seq) can retrieve a message whatever
          # its status, so a sailor can re-request a message already bundled
          # (e.g. lost or corrupted on reception over the radio link). Broad
          # wildcards stay limited to bundleable messages to avoid pulling the
          # whole history by accident over a scarce radio link.
          parsed = MessageDigest.decompose_hutmail_reference(id_str)
          scope = scope.bundleable unless precise_reference?(parsed)
          scope = scope.where("DATE(message_digests.date) = ?", parsed[:date]) if parsed[:date]
          scope = scope.where(mail_accounts: { short_code: parsed[:short_code] }) if parsed[:short_code]
          scope = scope.where("message_digests.daily_sequence = ?", parsed[:sequence]) if parsed[:sequence]
          scope
        end

        all_messages = all_messages.or(messages)
      end

      all_messages
    end

    def precise_reference?(parsed)
      parsed[:date].present? && parsed[:short_code].present? && parsed[:sequence].present?
    end

    def subject_for_reply(original)
      subject = original.subject.to_s
      subject.match?(/\ARe:\s/i) ? subject : "Re: #{subject}"
    end

    def extract_subject(body_lines)
      directive_subject, remaining = Vessel::SubjectDirective.extract(body_lines.join)
      [ directive_subject.presence || "Hutmail message", remaining.strip ]
    end

    def flush_outbound_block(block, results)
      return unless block

      if block[:body].join.strip.empty?
        flush_empty_send_block(block, results) if block[:kind] == :send
        return
      end

      case block[:kind]
      when :reply then flush_outbound_reply(block[:target], block[:body], results)
      when :msg   then flush_outbound_message(block[:short_code], block[:target], block[:body], results)
      when :send  then flush_outbound_send(block, results)
      end
    end

    def flush_empty_send_block(block, results)
      label = block[:urgent] ? "URGENT" : "SEND"
      report_error(results, source: "body", command: "#{label}.#{block[:short_code]} #{block[:target]}",
        message: "Empty message. Provide text after the command line.")
    end

    def flush_outbound_send(block, results)
      label = block[:urgent] ? "URGENT" : "SEND"

      if block[:short_code].blank?
        report_error(results, source: "body", command: label,
          message: "Invalid format. Use: #{label}.<ACCOUNT> <email>")
        return
      end

      account = mail_accounts.find_by(short_code: block[:short_code])
      unless account
        report_error(results, source: "body", command: "#{label}.#{block[:short_code]}",
          message: "Unknown account short_code: #{block[:short_code]}")
        return
      end

      subject, body = extract_subject(block[:body])
      reply = vessel_replies.create!(
        mail_account: account,
        message_digest: nil,
        to_address: block[:target],
        subject: subject,
        body: body,
        status: "pending"
      )

      if block[:urgent]
        reply.deliver_now
      else
        reply.deliver_later
      end

      results << { command: "#{label}.#{block[:short_code]} #{block[:target]}", status: :ok, message: "Message queued" }
    end

    def flush_outbound_reply(hutmail_ref, body, results)
      original = resolve_message_by_hutmail_reference(hutmail_ref)

      unless original
        report_error(results, source: "body", command: "REPLY #{hutmail_ref}",
          message: "Unknown hutmail_id: #{hutmail_ref}")
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
        report_error(results, source: "body", command: "MSG #{recipient}",
          message: "Invalid format. Use: ===MSG.<ACCOUNT> <email>===")
        return
      end

      account = mail_accounts.find_by(short_code: short_code)
      unless account
        report_error(results, source: "body", command: "MSG.#{short_code}",
          message: "Unknown account short_code: #{short_code}")
        return
      end

      subject, message_body = extract_subject(body)
      vessel_replies.create!(
        mail_account: account,
        message_digest: nil,
        to_address: recipient,
        subject: subject,
        body: message_body,
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
