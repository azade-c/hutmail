require "application_system_test_case"

class TrackMapTest < ApplicationSystemTestCase
  setup do
    @vessel = vessels(:one)
    @vessel.position_reports.create!(reported_at: Time.utc(2026, 11, 5, 14, 30), latitude: -12.5, longitude: -38.5)
    @vessel.position_reports.create!(reported_at: Time.utc(2026, 11, 6, 6, 0), latitude: -13.25, longitude: -39.125)
  end

  # The fixes themselves are drawn on a canvas, so the boat is the only marker
  # with a DOM node to look for. That suits us: it is the one that was asked
  # for by name.
  test "the boat sits on the last known fix" do
    visit track_path(@vessel.track_slug)

    assert_selector ".leaflet-container"
    assert_selector ".track-boat svg", count: 1, visible: :all
  end

  test "hovering the boat shows the date of the fix" do
    visit track_path(@vessel.track_slug)

    assert_selector ".track-boat"
    assert_no_selector ".leaflet-tooltip"

    find(".track-boat").hover

    assert_selector ".leaflet-tooltip", text: "2026-11-06 06:00Z"
  end
end
