require "test_helper"

class RelayMailerTest < ActionMailer::TestCase
  setup do
    @vessel = vessels(:one)
    @bundle = Bundle.create!(
      vessel: @vessel,
      status: "sent",
      sent_at: Time.current,
      messages_count: 0,
      total_stripped_size: 0,
      bundle_text: "=== HUTMAIL test ===\n"
    )
  end

  test "sets HUTMAIL subject and bundle body" do
    mail = RelayMailer.new.send_bundle(@bundle)
    assert_match(/\AHUTMAIL/, mail.subject)
    assert_equal @vessel.sailmail_address, mail.to.first
    assert_includes mail.body.to_s, "HUTMAIL test"
  end

  test "does not set X-Hutmail-* identifying headers" do
    mail = RelayMailer.new.send_bundle(@bundle)

    assert_nil mail["X-Hutmail-Version"]
    assert_nil mail["X-Hutmail-Kind"]
    assert_nil mail["X-Hutmail-Vessel-Id"]
    assert_nil mail["X-Hutmail-Bundle-Id"]
  end
end
