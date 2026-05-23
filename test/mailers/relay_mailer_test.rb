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

  test "sets X-Hutmail-* identifying headers on every bundle" do
    mail = RelayMailer.new.send_bundle(@bundle)

    assert_equal "1", mail["X-Hutmail-Version"].value
    assert_equal "bundle", mail["X-Hutmail-Kind"].value
    assert_equal @vessel.id.to_s, mail["X-Hutmail-Vessel-Id"].value
    assert_equal @bundle.id.to_s, mail["X-Hutmail-Bundle-Id"].value
  end
end
