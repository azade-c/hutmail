module MessageDigest::Identifiable
  extend ActiveSupport::Concern

  MONTHS = %w[jan feb mar apr may jun jul aug sep oct nov dec].freeze

  included do
    before_validation :assign_daily_sequence, on: :create, if: -> { daily_sequence.blank? }
  end

  class_methods do
    def decompose_hutmail_reference(input)
      input = input.strip
      parts = input.split(".")
      return {} if parts.empty?

      date = parse_date_part(parts[0])
      short_code = parts[1]&.upcase
      sequence = parts[2]&.to_i

      { date:, short_code:, sequence: }.compact
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

  def reference_date
    date&.to_date || collected_at&.to_date || Date.current
  end

  def hutmail_reference(long: false)
    prefix = reference_prefix(long:)
    "#{prefix}.#{short_code}.#{daily_sequence}"
  end

  def hutmail_reference_parts
    self.class.decompose_hutmail_reference(hutmail_reference(long: true))
  end

  private
    def assign_daily_sequence
      return unless mail_account.present?

      self.daily_sequence = next_daily_sequence
    end

    def next_daily_sequence
      mail_account.message_digests
        .where(date: reference_date.all_day)
        .maximum(:daily_sequence)
        .to_i + 1
    end

    def reference_prefix(long:)
      ref_date = reference_date
      day = ref_date.day.to_s.rjust(2, "0")
      month = MONTHS[ref_date.month - 1]
      year = ref_date.year.to_s[-2..]

      if long || ref_date.year != Date.current.year
        "#{day}#{month}#{year}"
      else
        "#{day}#{month}"
      end
    end
end
