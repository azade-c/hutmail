require "test_helper"

class PositionReport::NumberingTest < ActiveSupport::TestCase
  setup do
    @vessel = vessels(:one)
  end

  test "the first report of a vessel is number one" do
    report = report_at(Time.utc(2026, 11, 5))

    assert_equal 1, report.sequence
    assert_equal "n° 1", report.number_label
  end

  test "numbers are handed out in order of arrival" do
    first = report_at(Time.utc(2026, 11, 5))
    second = report_at(Time.utc(2026, 11, 6))

    assert_equal [ 1, 2 ], [ first.sequence, second.sequence ]
  end

  # This is the whole point of storing the number rather than counting the
  # points: POSREPORTDEL 12 has to still mean point 12 tomorrow.
  test "deleting a point leaves the others numbered as they were" do
    first = report_at(Time.utc(2026, 11, 5))
    second = report_at(Time.utc(2026, 11, 6))
    third = report_at(Time.utc(2026, 11, 7))

    second.destroy!

    assert_equal [ 1, 3 ], [ first.reload.sequence, third.reload.sequence ]
  end

  test "a number freed by a deletion is never handed out again" do
    report_at(Time.utc(2026, 11, 5))
    report_at(Time.utc(2026, 11, 6)).destroy!

    assert_equal 3, report_at(Time.utc(2026, 11, 7)).sequence
  end

  # A repeated timestamp corrects a point in place, so it keeps its number: the
  # skipper who read it off the map is still holding the right one.
  test "correcting a point keeps its number" do
    report = report_at(Time.utc(2026, 11, 5), latitude: 1)
    report_at(Time.utc(2026, 11, 6))

    report.update!(latitude: 2)

    assert_equal 1, report.reload.sequence
  end

  test "two vessels number their own tracks independently" do
    other = Vessel.create!(name: "Bilbo", sailmail_address: "BLB1@sailmail.com",
      relay_account: RelayAccount.new(relay_accounts(:one).attributes.except("id", "vessel_id")))

    assert_equal 1, report_at(Time.utc(2026, 11, 5)).sequence
    assert_equal 1, other.position_reports.create!(reported_at: Time.utc(2026, 11, 5), latitude: 1, longitude: 1).sequence
  end

  private
    def report_at(time, latitude: 1, longitude: 1)
      @vessel.position_reports.create!(reported_at: time, latitude: latitude, longitude: longitude)
    end
end
