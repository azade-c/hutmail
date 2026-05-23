module Vessel::Scheduling
  extend ActiveSupport::Concern

  CADENCES = %w[manual every_hours daily].freeze
  DAILY_AT_FORMAT = /\A([01]\d|2[0-3]):[0-5]\d\z/
  COMMON_TIMEZONES = %w[
    UTC
    Europe/Paris
    Europe/Lisbon
    Atlantic/Azores
    Atlantic/Cape_Verde
    America/Martinique
    America/New_York
    America/Panama
    Pacific/Tahiti
    Pacific/Auckland
  ].freeze

  included do
    validates :dispatch_cadence, inclusion: { in: CADENCES }
    validates :dispatch_timezone, inclusion: { in: ->(_) { ActiveSupport::TimeZone::MAPPING.keys + ActiveSupport::TimeZone::MAPPING.values } }
    validates :dispatch_every_hours, numericality: { only_integer: true, in: 1..24 }, if: -> { dispatch_cadence == "every_hours" }
    validates :dispatch_daily_at, format: { with: DAILY_AT_FORMAT }, if: -> { dispatch_cadence == "daily" }

    before_save :recompute_next_dispatch_at, if: :schedule_attributes_changed?

    scope :due_for_dispatch, -> { where.not(next_dispatch_at: nil).where(next_dispatch_at: ..Time.current) }
  end

  def compute_next_dispatch_at(from: Time.current)
    case dispatch_cadence
    when "every_hours"
      base = last_dispatched_at || from
      base + dispatch_every_hours.hours
    when "daily"
      tz = ActiveSupport::TimeZone[dispatch_timezone] || ActiveSupport::TimeZone["UTC"]
      hour, minute = dispatch_daily_at.split(":").map(&:to_i)
      candidate = tz.now.change(hour: hour, min: minute, sec: 0)
      candidate += 1.day if candidate <= from.in_time_zone(tz)
      candidate.utc
    end
  end

  private
    SCHEDULE_ATTRS = %w[dispatch_cadence dispatch_every_hours dispatch_daily_at dispatch_timezone last_dispatched_at].freeze

    def schedule_attributes_changed?
      (changed & SCHEDULE_ATTRS).any?
    end

    def recompute_next_dispatch_at
      self.next_dispatch_at = compute_next_dispatch_at
    end
end
