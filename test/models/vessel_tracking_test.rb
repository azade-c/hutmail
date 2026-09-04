require "test_helper"

class VesselTrackingTest < ActiveSupport::TestCase
  setup do
    @vessel = vessels(:one)
  end

  test "a new vessel gets a link without being asked" do
    token = Vessel.new.track_token

    assert_match Vessel::Tracking::TOKEN_FORMAT, token
    assert_equal Vessel::Tracking::TOKEN_LENGTH, token.length
  end

  test "the skipper can choose the link by hand" do
    @vessel.update!(track_token: "AlibiEnRouteVersLeSud")

    assert_equal "AlibiEnRouteVersLeSud", @vessel.reload.track_token
  end

  test "whitespace around a pasted link is trimmed off" do
    @vessel.update!(track_token: "  AlibiEnRouteVersLeSud\n")

    assert_equal "AlibiEnRouteVersLeSud", @vessel.reload.track_token
  end

  # Clearing the field is the revocation path: there is no other way to retire a
  # URL that has been forwarded once too often.
  test "clearing the link draws a new one" do
    was = @vessel.track_token

    @vessel.update!(track_token: "")

    assert_not_equal was, @vessel.track_token
    assert_match Vessel::Tracking::TOKEN_FORMAT, @vessel.track_token
  end

  test "a field holding nothing but spaces counts as cleared" do
    was = @vessel.track_token

    @vessel.update!(track_token: "   ")

    assert_not_equal was, @vessel.track_token
    assert_match Vessel::Tracking::TOKEN_FORMAT, @vessel.track_token
  end

  test "a link too short to be unguessable is refused" do
    @vessel.track_token = "a" * 15

    assert_not @vessel.valid?
    assert @vessel.errors.of_kind?(:track_token, :invalid)
  end

  test "sixteen characters is enough and sixty-four is the ceiling" do
    @vessel.track_token = "a" * 16
    assert @vessel.valid?, @vessel.errors.full_messages.to_sentence

    @vessel.track_token = "a" * 64
    assert @vessel.valid?, @vessel.errors.full_messages.to_sentence

    @vessel.track_token = "a" * 65
    assert_not @vessel.valid?
  end

  test "anything a radio operator could mishear is refused" do
    [ "avec-un-tiret-1234", "avec un espace 12", "accentué1234567890", "point.kml.1234567" ].each do |candidate|
      @vessel.track_token = candidate

      assert_not @vessel.valid?, "#{candidate.inspect} should not be accepted"
      assert @vessel.errors.of_kind?(:track_token, :invalid)
    end
  end

  test "two vessels cannot share a link" do
    other = Vessel.new(track_token: @vessel.track_token)

    assert_not other.valid?
    assert other.errors.of_kind?(:track_token, :taken)
  end

  test "regenerate_track_token still replaces the link" do
    was = @vessel.track_token

    @vessel.regenerate_track_token

    assert_not_equal was, @vessel.reload.track_token
  end
end
