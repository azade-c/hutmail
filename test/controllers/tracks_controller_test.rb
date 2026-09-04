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
    get "/suivi/nope"

    assert_response :not_found
  end

  test "the English path the route used to answer on is gone" do
    get "/track/#{@vessel.track_token}"

    assert_response :not_found
  end

  # The route constraint and Vessel::Tracking::TOKEN_FORMAT are written out in
  # two files that cannot see each other. Should they ever drift, a token the
  # skipper was allowed to save would 404 for the family ashore.
  test "the route accepts exactly the tokens the model allows" do
    %W[
      #{"a" * 16} #{"a" * 24} #{"a" * 64} Alib1EnRouteVersLeSud
      #{"a" * 15} #{"a" * 65} nope avec-un-tiret-1234
    ].each do |candidate|
      assert_equal model_accepts?(candidate), route_matches?(candidate),
        "#{candidate.inspect}: model and route disagree"
    end
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

  test "the trace is downloadable as KML for Google Earth" do
    @vessel.position_reports.create!(reported_at: Time.utc(2026, 11, 5, 14, 30), latitude: 1.5, longitude: -2.5)
    @vessel.position_reports.create!(reported_at: Time.utc(2026, 11, 6, 6, 0), latitude: 2.5, longitude: -3.5)

    get track_path(@vessel.track_token, format: :kml)

    assert_response :success
    assert_equal "application/vnd.google-earth.kml+xml", response.media_type
    assert_match "<coordinates>-2.5,1.5,0 -3.5,2.5,0</coordinates>", response.body
  end

  test "the KML carries the timestamps Google Earth replays a crossing with" do
    @vessel.position_reports.create!(reported_at: Time.utc(2026, 11, 5, 14, 30), latitude: 1, longitude: 1)

    get track_path(@vessel.track_token, format: :kml)

    assert_match "<when>2026-11-05T14:30:00Z</when>", response.body
    assert_match "<gx:coord>1.0 1.0 0</gx:coord>", response.body
  end

  test "the KML is well-formed XML Google Earth will accept" do
    @vessel.update!(name: "Alibi & <Cie>")
    @vessel.position_reports.create!(reported_at: Time.utc(2026, 11, 5), latitude: 1, longitude: 1)

    get track_path(@vessel.track_token, format: :kml)

    document = Nokogiri::XML(response.body, &:strict)
    assert_equal "kml", document.root.name
    assert_equal "Alibi & <Cie>", document.at_xpath("//xmlns:Document/xmlns:name").text
    assert_equal 1, document.xpath("//gx:Track", "gx" => "http://www.google.com/kml/ext/2.2").size
  end

  test "an unknown token is a 404 for the KML too" do
    get track_path("notatrackingtokenatall", format: :kml)

    assert_response :not_found
  end

  test "a vessel without a single fix still renders valid KML" do
    get track_path(@vessel.track_token, format: :kml)

    assert_response :success
    assert_match "</kml>", response.body
    assert_no_match(/<coordinates>/, response.body)
  end

  test "the trace page offers the KML download" do
    @vessel.position_reports.create!(reported_at: Time.utc(2026, 11, 5), latitude: 1, longitude: 1)

    get track_path(@vessel.track_token)

    assert_select "a[href=?]", track_path(@vessel.track_token, format: :kml)
  end

  test "the vessel page links to the shareable trace" do
    sign_in_as users(:one)

    get vessel_path(@vessel)

    assert_response :success
    assert_select "a[href=?]", track_path(@vessel.track_token)
  end

  private
    def model_accepts?(token)
      vessel = Vessel.new(track_token: token)
      vessel.valid?

      !vessel.errors.include?(:track_token)
    end

    def route_matches?(token)
      Rails.application.routes.recognize_path("/suivi/#{token}")
      true
    rescue ActionController::RoutingError
      false
    end
end
