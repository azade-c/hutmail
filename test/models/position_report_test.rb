require "test_helper"

class PositionReportTest < ActiveSupport::TestCase
  setup do
    @vessel = vessels(:one)
  end

  # ------------------------------------------------------------------
  # Parsing the command arguments
  # ------------------------------------------------------------------

  test "parses a signed decimal position" do
    attributes = PositionReport.parse_command("2026-11-05 1430 45.2563 2.2570")

    assert_equal Time.utc(2026, 11, 5, 14, 30), attributes[:reported_at]
    assert_in_delta 45.2563, attributes[:latitude], 1e-6
    assert_in_delta 2.2570, attributes[:longitude], 1e-6
  end

  test "parses negative coordinates" do
    attributes = PositionReport.parse_command("2026-11-05 1430 -12.5 -38.5")

    assert_in_delta(-12.5, attributes[:latitude], 1e-6)
    assert_in_delta(-38.5, attributes[:longitude], 1e-6)
  end

  test "reads hemisphere suffixes the way a plotter shows them" do
    attributes = PositionReport.parse_command("2026-11-05 1430 12.5S 38.5W")

    assert_in_delta(-12.5, attributes[:latitude], 1e-6)
    assert_in_delta(-38.5, attributes[:longitude], 1e-6)
  end

  test "a hemisphere suffix wins over a stray sign" do
    attributes = PositionReport.parse_command("2026-11-05 1430 -12.5N -38.5E")

    assert_in_delta 12.5, attributes[:latitude], 1e-6
    assert_in_delta 38.5, attributes[:longitude], 1e-6
  end

  test "accepts a colon in the time and a trailing Z" do
    attributes = PositionReport.parse_command("2026-11-05 14:30Z 45.2563 2.2570")

    assert_equal Time.utc(2026, 11, 5, 14, 30), attributes[:reported_at]
  end

  test "is case insensitive on hemispheres" do
    attributes = PositionReport.parse_command("2026-11-05 1430 12.5s 38.5w")

    assert_in_delta(-12.5, attributes[:latitude], 1e-6)
    assert_in_delta(-38.5, attributes[:longitude], 1e-6)
  end

  test "returns nil on garbage" do
    assert_nil PositionReport.parse_command(nil)
    assert_nil PositionReport.parse_command("")
    assert_nil PositionReport.parse_command("somewhere nice")
    assert_nil PositionReport.parse_command("2026-11-05 1430 45.2563")
    assert_nil PositionReport.parse_command("05/11/2026 1430 45.2563 2.2570")
  end

  test "returns nil on an impossible clock time" do
    assert_nil PositionReport.parse_command("2026-11-05 2530 45.2563 2.2570")
  end

  test "returns nil on a date that does not exist" do
    assert_nil PositionReport.parse_command("2026-02-30 1430 45.2563 2.2570")
  end

  # ------------------------------------------------------------------
  # Validation
  # ------------------------------------------------------------------

  test "rejects coordinates off the planet" do
    report = @vessel.position_reports.build(
      PositionReport.parse_command("2026-11-05 1430 91.0 2.2570")
    )

    assert_not report.valid?
    assert_includes report.errors.attribute_names, :latitude
  end

  test "rejects a longitude past the antimeridian" do
    report = @vessel.position_reports.build(
      reported_at: Time.utc(2026, 11, 5, 14, 30), latitude: 0, longitude: 181
    )

    assert_not report.valid?
    assert_includes report.errors.attribute_names, :longitude
  end

  test "refuses two fixes at the same instant for one vessel" do
    @vessel.position_reports.create!(reported_at: Time.utc(2026, 11, 5, 14, 30), latitude: 1, longitude: 2)

    assert_raises ActiveRecord::RecordNotUnique do
      @vessel.position_reports.create!(reported_at: Time.utc(2026, 11, 5, 14, 30), latitude: 3, longitude: 4)
    end
  end

  # ------------------------------------------------------------------
  # Distances
  # ------------------------------------------------------------------

  test "one degree of latitude is sixty nautical miles" do
    from = @vessel.position_reports.build(reported_at: Time.utc(2026, 11, 5), latitude: 0, longitude: 0)
    to = @vessel.position_reports.build(reported_at: Time.utc(2026, 11, 6), latitude: 1, longitude: 0)

    assert_in_delta 60.0, from.distance_nm_to(to), 0.1
  end

  test "distance to nothing is zero" do
    report = @vessel.position_reports.build(reported_at: Time.utc(2026, 11, 5), latitude: 10, longitude: 10)

    assert_equal 0.0, report.distance_nm_to(nil)
  end

  test "total distance sums the legs of the trace" do
    reports = [
      [ 0, 0 ], [ 1, 0 ], [ 2, 0 ]
    ].each_with_index.map do |(lat, lon), index|
      @vessel.position_reports.build(reported_at: Time.utc(2026, 11, 5 + index), latitude: lat, longitude: lon)
    end

    assert_in_delta 120.0, PositionReport.total_distance_nm(reports), 0.2
  end

  test "total distance of a single fix is zero" do
    report = @vessel.position_reports.build(reported_at: Time.utc(2026, 11, 5), latitude: 1, longitude: 1)

    assert_equal 0, PositionReport.total_distance_nm([ report ])
    assert_equal 0, PositionReport.total_distance_nm([])
  end

  # ------------------------------------------------------------------
  # Labels
  # ------------------------------------------------------------------

  test "labels coordinates with hemispheres" do
    report = @vessel.position_reports.build(
      reported_at: Time.utc(2026, 11, 5, 14, 30), latitude: -12.5, longitude: -38.5
    )

    assert_equal "12.5S 38.5W", report.coordinates_label
    assert_equal "2026-11-05 14:30Z", report.reported_on_utc
  end
end
