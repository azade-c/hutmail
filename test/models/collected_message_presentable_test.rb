require "test_helper"

class CollectedMessagePresentableTest < ActiveSupport::TestCase
  setup do
    @account = mail_accounts(:gmail)
  end

  test "to_screener_line formats compactly" do
    msg = @account.collected_messages.create!(
      imap_uid: 100,
      imap_message_id: "screener-presentable@example.com",
      from_address: "bob@example.com",
      from_name: "Bob",
      subject: "Hello from land",
      date: Time.current,
      raw_size: 2000,
      stripped_body: "Hello!",
      stripped_size: 6,
      status: "pending",
      collected_at: Time.current
    )

    line = msg.to_screener_line
    assert_includes line, msg.hutmail_id
    assert_includes line, "Bob"
    assert_includes line, "Hello from land"
  end

  test "to_radio_text shows remaining attachments after the body" do
    msg = @account.collected_messages.create!(
      imap_uid: 101,
      imap_message_id: "attachments-after-body@example.com",
      from_address: "bob@example.com",
      from_name: "Bob",
      subject: "Photos",
      date: Time.current,
      raw_size: 3000,
      stripped_body: "Body first\n\n[image : inline-photo.jpg (2.0 KB)]\n\nSignature",
      stripped_size: 48,
      status: "pending",
      collected_at: Time.current,
      attachments_metadata: [
        { name: "inline-photo.jpg", size: 2048, content_type: "image/jpeg", inline: true },
        { name: "chart.jpg", size: 1024, content_type: "image/jpeg", inline: false }
      ]
    )

    text = msg.to_radio_text
    assert_includes text, "Body first"
    assert_includes text, "📎 chart.jpg (1.0 KB)"
    assert_not_includes text, "📎 inline-photo.jpg"
    assert text.index("Signature") < text.index("📎 chart.jpg (1.0 KB)")
  end
end
