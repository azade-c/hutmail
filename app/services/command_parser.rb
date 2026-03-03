# Parses commands sent from the boat via email
#
# Format:
#   ===CMD===
#   DROP LAST                — cancel/remove the last delivery (too big to download)
#   DROP 3 5                 — remove specific messages by number from next delivery
#   SEND bob@example.com "Message text here"
#   PAUSE 3d                — stop aggregation (shore leave, wifi)
#   RESUME                  — resume aggregation
#   STATUS                  — get a summary of pending messages
#   WHITELIST add bob@example.com
#   WHITELIST remove spam@junk.com
#   BLACKLIST add spam@junk.com
#   BLACKLIST remove bob@example.com
#   URGENT famille@castors.fr "Emergency message"
#   ===END===
#
class CommandParser
  Command = Data.define(:action, :args)

  ParseResult = Data.define(:commands, :errors) do
    def valid? = errors.empty?
  end

  VALID_ACTIONS = %w[DROP SEND PAUSE RESUME STATUS WHITELIST BLACKLIST URGENT].freeze

  def self.parse(text)
    commands = []
    errors = []

    # Extract the command block between ===CMD=== and ===END===
    match = text.match(/===CMD===(.*?)===END===/m)
    unless match
      return ParseResult.new(commands: [], errors: [ "No ===CMD=== ... ===END=== block found" ])
    end

    block = match[1].strip
    block.each_line.with_index(1) do |line, line_num|
      line = line.strip
      next if line.empty?
      next if line.start_with?("#") # comments

      tokens = tokenize(line)
      action = tokens.first&.upcase

      unless VALID_ACTIONS.include?(action)
        errors << "Line #{line_num}: unknown command '#{tokens.first}'"
        next
      end

      args = tokens[1..]

      case action
      when "DROP"
        if args.first&.upcase == "LAST"
          commands << Command.new(action: "DROP", args: { target: "last" })
        else
          nums = args.map { |a| a.to_i }
          if nums.empty? || nums.any? { |n| n < 1 }
            errors << "Line #{line_num}: DROP requires LAST or message numbers (e.g., DROP LAST or DROP 3 5)"
            next
          end
          commands << Command.new(action: "DROP", args: { target: "messages", indices: nums })
        end

      when "SEND"
        if args.size < 2
          errors << "Line #{line_num}: SEND requires an email and a message (e.g., SEND bob@example.com \"Hello\")"
          next
        end
        commands << Command.new(action: "SEND", args: { to: args[0], message: args[1..].join(" ") })

      when "URGENT"
        if args.size < 2
          errors << "Line #{line_num}: URGENT requires an email and a message"
          next
        end
        commands << Command.new(action: "URGENT", args: { to: args[0], message: args[1..].join(" ") })

      when "PAUSE"
        duration = args.first || "indefinite"
        commands << Command.new(action: "PAUSE", args: { duration: duration })

      when "RESUME"
        commands << Command.new(action: "RESUME", args: {})

      when "STATUS"
        commands << Command.new(action: "STATUS", args: {})

      when "WHITELIST", "BLACKLIST"
        sub_action = args[0]&.downcase
        email = args[1]
        unless %w[add remove].include?(sub_action) && email.present?
          errors << "Line #{line_num}: #{action} requires 'add' or 'remove' and an email"
          next
        end
        commands << Command.new(action: action, args: { sub_action: sub_action, email: email })
      end
    end

    ParseResult.new(commands: commands, errors: errors)
  end

  # Apply parsed commands, returning the execution result
  def self.execute(commands, message_count:)
    drop_indices = []
    drop_last = false
    actions_log = []

    commands.each do |cmd|
      case cmd.action
      when "DROP"
        if cmd.args[:target] == "last"
          drop_last = true
          actions_log << "🗑️ DROP LAST — cancel previous delivery (boat should not download it)"
        else
          indices = cmd.args[:indices]
          invalid = indices.select { |i| i > message_count }
          valid = indices.select { |i| i >= 1 && i <= message_count }
          drop_indices.concat(valid)
          actions_log << "🗑️ DROP messages: #{valid.join(', ')} — will be excluded from next delivery"
          if invalid.any?
            actions_log << "⚠️ Invalid message numbers (max is ##{message_count}): #{invalid.join(', ')}"
          end
        end

      when "SEND"
        actions_log << "📤 SEND to #{cmd.args[:to]}: \"#{cmd.args[:message].truncate(60)}\""

      when "URGENT"
        actions_log << "🚨 URGENT to #{cmd.args[:to]}: \"#{cmd.args[:message].truncate(60)}\""

      when "PAUSE"
        actions_log << "⏸️ PAUSE aggregation for #{cmd.args[:duration]}"

      when "RESUME"
        actions_log << "▶️ RESUME aggregation"

      when "STATUS"
        actions_log << "📊 STATUS requested — will send summary to boat"

      when "WHITELIST"
        actions_log << "✅ WHITELIST #{cmd.args[:sub_action]} #{cmd.args[:email]}"

      when "BLACKLIST"
        actions_log << "🚫 BLACKLIST #{cmd.args[:sub_action]} #{cmd.args[:email]}"
      end
    end

    {
      drop_indices: drop_indices.uniq.sort,
      drop_last: drop_last,
      actions_log: actions_log
    }
  end

  # Tokenize a command line, respecting quoted strings
  def self.tokenize(line)
    tokens = []
    scanner = StringScanner.new(line)

    until scanner.eos?
      scanner.skip(/\s+/)
      break if scanner.eos?

      if scanner.peek(1) == '"'
        scanner.getch
        token = scanner.scan_until(/"/) || scanner.rest
        token = token.chomp('"')
        tokens << token
      else
        tokens << scanner.scan(/\S+/)
      end
    end

    tokens
  end
  private_class_method :tokenize
end
