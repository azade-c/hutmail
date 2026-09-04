class PositionReport < ApplicationRecord
  EARTH_RADIUS_NM = 3440.065

  # POSREPORT 2026-11-05 1430 45.2563 2.2570
  #
  # Date and time are always UTC. Latitude and longitude are decimal degrees,
  # either signed (-2.2570) or suffixed with a hemisphere (2.2570W) because
  # that is how a sailor reads them off a plotter.
  COMMAND_FORMAT = /\A
    (\d{4})-(\d{2})-(\d{2})                \s+
    (\d{2}):?(\d{2})Z?                     \s+
    ([+-]?\d{1,3}(?:\.\d+)?)\s*([NS])?     \s+
    ([+-]?\d{1,3}(?:\.\d+)?)\s*([EW])?
  \z/xi

  belongs_to :vessel

  validates :reported_at, presence: true
  validates :latitude, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }
  validates :longitude, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }

  scope :chronological, -> { order(:reported_at) }

  # Returns the attributes of a report, or nil when the arguments are not a
  # position report at all. Coordinates are not range-checked here: that is the
  # record's job, so the caller can tell "not a position" from "not on Earth".
  def self.parse_command(args)
    return nil if args.blank?

    match = args.to_s.strip.match(COMMAND_FORMAT)
    return nil unless match

    year, month, day, hour, minute, lat, lat_hemisphere, lon, lon_hemisphere = match.captures

    # Time.utc happily rolls 2026-02-30 over into March, so the date is checked
    # separately: a typo in a position report must be rejected, not relocated.
    return nil unless Date.valid_date?(year.to_i, month.to_i, day.to_i)

    reported_at =
      begin
        Time.utc(year.to_i, month.to_i, day.to_i, hour.to_i, minute.to_i)
      rescue ArgumentError
        return nil
      end

    {
      reported_at: reported_at,
      latitude: signed_coordinate(lat, lat_hemisphere, negative: "S"),
      longitude: signed_coordinate(lon, lon_hemisphere, negative: "W")
    }
  end

  # Sum of the legs of an already-ordered list of reports.
  def self.total_distance_nm(reports)
    reports.each_cons(2).sum { |from, to| from.distance_nm_to(to) }
  end

  def self.signed_coordinate(value, hemisphere, negative:)
    degrees = value.to_f
    return degrees if hemisphere.blank?

    hemisphere.upcase == negative ? -degrees.abs : degrees.abs
  end
  private_class_method :signed_coordinate

  def reported_on_utc
    reported_at.utc.strftime("%Y-%m-%d %H:%MZ")
  end

  def reported_at_iso8601
    reported_at.utc.iso8601
  end

  # KML reads longitude first, then latitude, then altitude.
  def kml_coordinates
    "#{longitude.to_f},#{latitude.to_f},0"
  end

  # gx:Track separates its coordinates with spaces where KML uses commas.
  def kml_track_coordinates
    kml_coordinates.tr(",", " ")
  end

  def coordinates_label
    "#{format_degrees(latitude, 'N', 'S')} #{format_degrees(longitude, 'E', 'W')}"
  end

  # Great-circle distance in nautical miles. Good enough for a trace on a map;
  # nobody navigates from this.
  def distance_nm_to(other)
    return 0.0 unless other

    lat1, lon1, lat2, lon2 = [ latitude, longitude, other.latitude, other.longitude ].map { |d| d.to_f * Math::PI / 180 }

    haversine = Math.sin((lat2 - lat1) / 2)**2 +
      (Math.cos(lat1) * Math.cos(lat2) * Math.sin((lon2 - lon1) / 2)**2)

    2 * EARTH_RADIUS_NM * Math.asin([ Math.sqrt(haversine), 1.0 ].min)
  end

  private
    def format_degrees(value, positive, negative)
      degrees = value.to_f
      "#{degrees.abs.round(4)}#{degrees.negative? ? negative : positive}"
    end
end
