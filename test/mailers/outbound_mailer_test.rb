require "test_helper"

class OutboundMailerTest < ActionMailer::TestCase
  setup do
    @account = mail_accounts(:gmail)
    @vessel = vessels(:one)
  end

  test "sets In-Reply-To and References when reply is linked to a MessageDigest" do
    original = MessageDigest.create!(
      mail_account: @account,
      from_address: "alice@example.com",
      subject: "Original thread",
      date: 1.day.ago,
      imap_message_id: "orig-abc-123@example.com",
      imap_uid: 11,
      raw_size: 100, stripped_body: "x", stripped_size: 1,
      daily_sequence: 1, status: "bundled", collected_at: 1.day.ago
    )

    reply = VesselReply.create!(
      vessel: @vessel, mail_account: @account, message_digest: original,
      to_address: "alice@example.com", subject: "Re: Original thread",
      body: "Greetings from the sea", status: "pending"
    )

    mail = OutboundMailer.new.send_reply(reply)

    assert_equal "<orig-abc-123@example.com>", mail["In-Reply-To"].value
    assert_equal "<orig-abc-123@example.com>", mail["References"].value
    assert_equal "Re: Original thread", mail.subject
  end

  test "wraps bare Message-ID in angle brackets if needed" do
    original = MessageDigest.create!(
      mail_account: @account,
      from_address: "bob@example.com",
      subject: "Bare id",
      date: 1.day.ago,
      imap_message_id: "<already-wrapped@example.com>",
      imap_uid: 12,
      raw_size: 100, stripped_body: "x", stripped_size: 1,
      daily_sequence: 1, status: "bundled", collected_at: 1.day.ago
    )

    reply = VesselReply.create!(
      vessel: @vessel, mail_account: @account, message_digest: original,
      to_address: "bob@example.com", subject: "Re: Bare id",
      body: "ok", status: "pending"
    )

    mail = OutboundMailer.new.send_reply(reply)

    assert_equal "<already-wrapped@example.com>", mail["In-Reply-To"].value
  end

  test "omits threading headers when no MessageDigest is linked" do
    reply = VesselReply.create!(
      vessel: @vessel, mail_account: @account, message_digest: nil,
      to_address: "new@example.com", subject: "HutMail reply",
      body: "first contact", status: "pending"
    )

    mail = OutboundMailer.new.send_reply(reply)

    assert_nil mail["In-Reply-To"]
    assert_nil mail["References"]
  end
end
