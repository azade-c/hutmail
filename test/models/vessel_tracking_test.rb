require "test_helper"

class VesselTrackingTest < ActiveSupport::TestCase
  setup do
    @vessel = vessels(:one)
  end

  test "a new vessel gets a link without being asked" do
    vessel = Vessel.new
    vessel.valid?

    assert_match Vessel::Tracking::SLUG_FORMAT, vessel.track_slug
    assert_equal Vessel::Tracking::SLUG_LENGTH, vessel.track_slug.length
  end

  test "the skipper can choose the link by hand" do
    @vessel.update!(track_slug: "AlibiEnRouteVersLeSud")

    assert_equal "AlibiEnRouteVersLeSud", @vessel.reload.track_slug
  end

  test "whitespace around a pasted link is trimmed off" do
    @vessel.update!(track_slug: "  AlibiEnRouteVersLeSud\n")

    assert_equal "AlibiEnRouteVersLeSud", @vessel.reload.track_slug
  end

  # Clearing the field is the revocation path: there is no other way to retire a
  # URL that has been forwarded once too often.
  test "clearing the link draws a new one" do
    was = @vessel.track_slug

    @vessel.update!(track_slug: "")

    assert_not_equal was, @vessel.track_slug
    assert_match Vessel::Tracking::SLUG_FORMAT, @vessel.track_slug
  end

  test "a field holding nothing but spaces counts as cleared" do
    was = @vessel.track_slug

    @vessel.update!(track_slug: "   ")

    assert_not_equal was, @vessel.track_slug
    assert_match Vessel::Tracking::SLUG_FORMAT, @vessel.track_slug
  end

  test "a link too short to be unguessable is refused" do
    @vessel.track_slug = "a" * 15

    assert_not @vessel.valid?
    assert @vessel.errors.of_kind?(:track_slug, :invalid)
  end

  test "sixteen characters is enough and sixty-four is the ceiling" do
    @vessel.track_slug = "a" * 16
    assert @vessel.valid?, @vessel.errors.full_messages.to_sentence

    @vessel.track_slug = "a" * 64
    assert @vessel.valid?, @vessel.errors.full_messages.to_sentence

    @vessel.track_slug = "a" * 65
    assert_not @vessel.valid?
  end

  test "anything a radio operator could mishear is refused" do
    [ "avec-un-tiret-1234", "avec un espace 12", "accentué1234567890", "point.kml.1234567" ].each do |candidate|
      @vessel.track_slug = candidate

      assert_not @vessel.valid?, "#{candidate.inspect} should not be accepted"
      assert @vessel.errors.of_kind?(:track_slug, :invalid)
    end
  end

  test "two vessels cannot share a link" do
    other = Vessel.new(track_slug: @vessel.track_slug)

    assert_not other.valid?
    assert other.errors.of_kind?(:track_slug, :taken)
  end

  # base58 leaves out 0, O, I and l on purpose: a slug drawn by the app has to
  # survive being read aloud over the radio, not just being clicked.
  test "a drawn link holds no character a radio operator would misread" do
    @vessel.update!(track_slug: "")

    assert_no_match(/[0OIl]/, @vessel.track_slug)
  end
end
