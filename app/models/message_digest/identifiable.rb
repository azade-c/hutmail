module MessageDigest::Identifiable
  extend ActiveSupport::Concern

  MONTHS = %w[jan feb mar apr may jun jul aug sep oct nov dec].freeze

  included do
    before_validation :assign_hutmail_id, on: :create, if: -> { hutmail_id.blank? }
  end

  class_methods do
    def decompose_hutmail_id(input)
      input = input.strip
      parts = input.split(".")
      return {} if parts.empty?

      date = parse_date_part(parts[0])
      short_code = parts[1]&.upcase
      sequence = parts[2]&.to_i

      { date: date, short_code: short_code, sequence: sequence }.compact
    end

    private
      def parse_date_part(str)
        match = str.match(/\A(\d{2})([a-z]{3})(\d{2})?\z/i)
        return nil unless match

        day = match[1].to_i
        month_idx = MONTHS.index(match[2].downcase)
        return nil unless month_idx

        year = match[3] ? 2000 + match[3].to_i : Date.current.year
        Date.new(year, month_idx + 1, day)
      rescue Date::Error
        nil
      end
  end

  def hutmail_id_parts
    self.class.decompose_hutmail_id(hutmail_id)
  end

  private
    def assign_hutmail_id
      return unless mail_account.present?

      date = self.date&.to_date || Date.current
      day = date.day.to_s.rjust(2, "0")
      month = MONTHS[date.month - 1]
      year_suffix = date.year != Date.current.year ? date.year.to_s[-2..] : ""
      code = mail_account.short_code

      prefix = "#{day}#{month}#{year_suffix}.#{code}."
      existing = mail_account.message_digests
        .where("hutmail_id LIKE ?", "#{prefix}%")
        .pluck(:hutmail_id)

      max_seq = existing.filter_map { |id| id.split(".").last.to_i }.max || 0
      self.hutmail_id = "#{prefix}#{max_seq + 1}"
    end
end
