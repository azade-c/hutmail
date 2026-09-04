require "test_helper"

class TracksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @vessel = vessels(:one)
  end

  test "the trace is reachable without authentication" do
    get track_path(@vessel.track_token)

    assert_response :success
    assert_select "h1", @vessel.name
  end

  test "an unknown token is a 404, not a redirect to the login page" do
    get track_path("notatrackingtokenatall")

    assert_response :not_found
  end

  test "a token too short to be one does not even match the route" do
    get "/track/nope"

    assert_response :not_found
  end

  test "the trace is kept out of search indexes" do
    get track_path(@vessel.track_token)

    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
  end

  test "position reports are handed to the map in chronological order" do
    @vessel.position_reports.create!(reported_at: Time.utc(2026, 11, 6, 6, 0), latitude: 2, longitude: 2)
    @vessel.position_reports.create!(reported_at: Time.utc(2026, 11, 5, 14, 30), latitude: 1, longitude: 1)

    get track_path(@vessel.track_token)

    assert_response :success
    points = JSON.parse(css_select("[data-controller='track-map']").first["data-track-map-points-value"])
    assert_equal [ 1.0, 2.0 ], points.map { |point| point["lat"] }
    assert_match(/2026-11-05 14:30Z/, points.first["label"])
  end

  test "the header sums the distance sailed" do
    @vessel.position_reports.create!(reported_at: Time.utc(2026, 11, 5), latitude: 0, longitude: 0)
    @vessel.position_reports.create!(reported_at: Time.utc(2026, 11, 6), latitude: 1, longitude: 0)

    get track_path(@vessel.track_token)

    assert_response :success
    assert_select ".track-header__stats", /60 nm/
  end

  test "a vessel without a single fix shows an empty trace, not a broken map" do
    get track_path(@vessel.track_token)

    assert_response :success
    assert_select ".track-empty"
    assert_select "[data-controller='track-map']", false
  end

  test "the vessel page links to the shareable trace" do
    sign_in_as users(:one)

    get vessel_path(@vessel)

    assert_response :success
    assert_select "a[href=?]", track_path(@vessel.track_token)
  end
end
