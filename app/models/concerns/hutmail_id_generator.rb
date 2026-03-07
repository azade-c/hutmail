module HutmailIdGenerator
  extend self

  MONTHS = %w[jan feb mar apr may jun jul aug sep oct nov dec].freeze

  # Generate a hutmail_id for a message: 01mar.GM.1
  def generate(mail_account:, date:)
    day = date.day.to_s.rjust(2, "0")
    month = MONTHS[date.month - 1]
    year_suffix = date.year != Date.current.year ? date.year.to_s[-2..] : ""
    code = mail_account.short_code

    # Find next sequence number for this account + date
    prefix = "#{day}#{month}#{year_suffix}.#{code}."
    existing = mail_account.collected_messages
      .where("hutmail_id LIKE ?", "#{prefix}%")
      .pluck(:hutmail_id)

    max_seq = existing.filter_map { |id| id.split(".").last.to_i }.max || 0

    "#{prefix}#{max_seq + 1}"
  end

  # Parse a hutmail_id or partial wildcard into filter criteria
  # Returns a hash: { date: Date, short_code: String, sequence: Integer }
  # Any key may be nil (wildcard)
  def parse(input)
    input = input.strip

    # Just a number: sequence wildcard (GET 1)
    if input.match?(/\A\d+\z/)
      return { date: nil, short_code: nil, sequence: input.to_i }
    end

    # Just 2 uppercase letters: mailbox wildcard (GET GM)
    if input.match?(/\A[A-Z]{2}\z/)
      return { date: nil, short_code: input, sequence: nil }
    end

    # Full or partial: DDmon[YY].BB.N or DDmon[YY].BB or DDmon[YY]
    parts = input.split(".")

    date = parse_date_part(parts[0]) if parts[0]

    if parts.length == 1
      { date: date, short_code: nil, sequence: nil }
    elsif parts.length == 2
      { date: date, short_code: parts[1].upcase, sequence: nil }
    else
      { date: date, short_code: parts[1].upcase, sequence: parts[2].to_i }
    end
  end

  private

  def parse_date_part(str)
    match = str.match(/\A(\d{2})([a-z]{3})(\d{2})?\z/i)
    return nil unless match

    day = match[1].to_i
    month_idx = MONTHS.index(match[2].downcase)
    return nil unless month_idx

    year = if match[3]
      2000 + match[3].to_i
    else
      Date.current.year
    end

    Date.new(year, month_idx + 1, day)
  rescue Date::Error
    nil
  end
end
