require "test_helper"

class MessageDigestPresentableTest < ActiveSupport::TestCase
  setup do
    @account = mail_accounts(:gmail)
  end

  test "to_screener_line formats compactly" do
    msg = @account.message_digests.create!(
      imap_uid: 100,
      imap_message_id: "screener-presentable@example.com",
      from_address: "bob@example.com",
      from_name: "Bob",
      subject: "Hello from land",
      date: Time.current,
      raw_size: 2000,
      stripped_body: "Hello!",
      stripped_size: 6,
      status: :collected,
      collected_at: Time.current
    )

    line = msg.to_screener_line
    assert_includes line, msg.hutmail_reference
    assert_includes line, "Bob"
    assert_includes line, "Hello from land"
  end

  test "to_radio_text shows remaining attachments after the body" do
    msg = @account.message_digests.create!(
      imap_uid: 101,
      imap_message_id: "attachments-after-body@example.com",
      from_address: "bob@example.com",
      from_name: "Bob",
      subject: "Photos",
      date: Time.current,
      raw_size: 3000,
      stripped_body: "Body first\n\n[image : inline-photo.jpg (2.0 KB)]\n\nSignature",
      stripped_size: 48,
      status: :collected,
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

  test "to_radio_text keeps a same-named attachment that differs from the embedded one" do
    msg = @account.message_digests.create!(
      imap_uid: 102,
      imap_message_id: "same-name-attachment@example.com",
      from_address: "bob@example.com",
      from_name: "Bob",
      subject: "Logos",
      date: Time.current,
      raw_size: 5000,
      stripped_body: "Body\n\n[image : logo.png (1.0 KB)]",
      stripped_size: 32,
      status: :collected,
      collected_at: Time.current,
      attachments_metadata: [
        { name: "logo.png", size: 1024, content_type: "image/png", inline: true },
        { name: "logo.png", size: 8192, content_type: "image/png", inline: false }
      ]
    )

    text = msg.to_radio_text
    assert_includes text, "📎 logo.png (8.0 KB)"
  end

  test "to_radio_text truncates the body and reports dropped characters when a limit is given" do
    body = "a" * 120
    msg = @account.message_digests.create!(
      imap_uid: 103,
      imap_message_id: "truncate-limit@example.com",
      from_address: "bob@example.com",
      from_name: "Bob",
      subject: "Long one",
      date: Time.current,
      raw_size: 5000,
      stripped_body: body,
      stripped_size: body.length,
      status: :collected,
      collected_at: Time.current
    )

    text = msg.to_radio_text(char_limit: 50)
    assert_includes text, "a" * 50
    assert_not_includes text, "a" * 51
    assert_includes text, "// message tronqué, restent 70 caractères //"
  end

  test "to_radio_text leaves the body intact when it fits within the limit" do
    body = "short body"
    msg = @account.message_digests.create!(
      imap_uid: 104,
      imap_message_id: "truncate-fits@example.com",
      from_address: "bob@example.com",
      from_name: "Bob",
      subject: "Fits",
      date: Time.current,
      raw_size: 5000,
      stripped_body: body,
      stripped_size: body.length,
      status: :collected,
      collected_at: Time.current
    )

    text = msg.to_radio_text(char_limit: 50)
    assert_includes text, body
    assert_not_includes text, "message tronqué"
  end

  test "to_radio_text never truncates when no limit is given" do
    body = "b" * 200
    msg = @account.message_digests.create!(
      imap_uid: 105,
      imap_message_id: "truncate-none@example.com",
      from_address: "bob@example.com",
      from_name: "Bob",
      subject: "No limit",
      date: Time.current,
      raw_size: 5000,
      stripped_body: body,
      stripped_size: body.length,
      status: :collected,
      collected_at: Time.current
    )

    text = msg.to_radio_text
    assert_includes text, body
    assert_not_includes text, "message tronqué"
  end
end
