require "test_helper"
require "net/imap"

class MailAccountCollectingTest < ActiveSupport::TestCase
  FakeEnvelope = Struct.new(:message_id)
  FakeFetch = Struct.new(:attr)

  setup do
    @account = vessels(:one).mail_accounts.create!(
      name: "Collecting Test",
      short_code: "CT",
      imap_server: "imap.example.com",
      imap_port: 993,
      imap_encryption: "ssl",
      imap_username: "test@example.com",
      imap_password: "secret",
      smtp_server: "smtp.example.com",
      smtp_port: 587,
      smtp_encryption: "starttls",
      smtp_username: "test@example.com",
      smtp_password: "secret",
      skip_already_read: true
    )
  end

  test "collect_now fetches unseen messages, dedups and stores attachments metadata" do
    @account.collected_messages.create!(
      imap_uid: 555,
      imap_message_id: "dup@example.com",
      from_address: "dup@example.com",
      status: "pending",
      date: Time.current,
      collected_at: Time.current,
      raw_size: 10,
      stripped_size: 5
    )

    raw_mail = <<~MAIL
      From: Bob <bob@example.com>
      To: crew@example.com
      Subject: New message
      Date: Mon, 08 Mar 2026 10:00:00 +0000
      MIME-Version: 1.0
      Content-Type: multipart/mixed; boundary="BOUND"

      --BOUND
      Content-Type: text/plain; charset="UTF-8"

      Hello crew

      --BOUND
      Content-Type: text/plain; name="note.txt"
      Content-Disposition: attachment; filename="note.txt"
      Content-Transfer-Encoding: base64

      SGVsbG8gYXR0YWNobWVudA==
      --BOUND--
    MAIL

    fake_imap = Object.new
    fake_imap.define_singleton_method(:login) { |_u, _p| true }
    fake_imap.define_singleton_method(:select) { |_box| true }
    fake_imap.define_singleton_method(:search) { |_query| [ 1, 2 ] }
    fake_imap.define_singleton_method(:fetch) do |uid, _attrs|
      if uid == 1
        [ FakeFetch.new({ "ENVELOPE" => FakeEnvelope.new("dup@example.com"), "BODY[]" => raw_mail, "RFC822.SIZE" => raw_mail.bytesize }) ]
      else
        [ FakeFetch.new({ "ENVELOPE" => FakeEnvelope.new("new@example.com"), "BODY[]" => raw_mail, "RFC822.SIZE" => raw_mail.bytesize }) ]
      end
    end
    fake_imap.define_singleton_method(:logout) { true }
    fake_imap.define_singleton_method(:disconnect) { true }

    original_new = Net::IMAP.method(:new)
    Net::IMAP.define_singleton_method(:new) do |_host, **_kwargs|
      fake_imap
    end

    count = @account.collect_now
    assert_equal 1, count

    msg = @account.collected_messages.find_by!(imap_message_id: "new@example.com")
    assert_equal "pending", msg.status
    assert_equal "Hello crew", msg.stripped_body
    assert_equal 1, msg.attachments_metadata.size
    assert_equal "note.txt", msg.attachments_metadata.first["name"]
  ensure
    Net::IMAP.define_singleton_method(:new, original_new)
  end

  test "collect_now skips messages from sailmail address" do
    vessel = @account.vessel
    sailmail_from = vessel.sailmail_address

    relay_mail = <<~MAIL
      From: #{sailmail_from}
      To: test@example.com
      Subject: Commands from boat
      Date: Mon, 08 Mar 2026 10:00:00 +0000

      ===CMD===
      STATUS
      ===END===
    MAIL

    normal_mail = <<~MAIL
      From: friend@example.com
      To: test@example.com
      Subject: Hello
      Date: Mon, 08 Mar 2026 11:00:00 +0000

      How are you?
    MAIL

    fake_imap = Object.new
    fake_imap.define_singleton_method(:login) { |_u, _p| true }
    fake_imap.define_singleton_method(:select) { |_box| true }
    fake_imap.define_singleton_method(:search) { |_query| [ 1, 2 ] }
    fake_imap.define_singleton_method(:fetch) do |uid, _attrs|
      if uid == 1
        [ FakeFetch.new({ "ENVELOPE" => FakeEnvelope.new("relay-cmd@sailmail.com"), "BODY[]" => relay_mail, "RFC822.SIZE" => relay_mail.bytesize }) ]
      else
        [ FakeFetch.new({ "ENVELOPE" => FakeEnvelope.new("friend-msg@example.com"), "BODY[]" => normal_mail, "RFC822.SIZE" => normal_mail.bytesize }) ]
      end
    end
    fake_imap.define_singleton_method(:logout) { true }
    fake_imap.define_singleton_method(:disconnect) { true }

    original_new = Net::IMAP.method(:new)
    Net::IMAP.define_singleton_method(:new) do |_host, **_kwargs|
      fake_imap
    end

    count = @account.collect_now
    assert_equal 1, count

    assert_not @account.collected_messages.exists?(imap_message_id: "relay-cmd@sailmail.com")
    assert @account.collected_messages.exists?(imap_message_id: "friend-msg@example.com")
  ensure
    Net::IMAP.define_singleton_method(:new, original_new)
  end

  test "collect_now returns 0 on imap connection error" do
    original_new = Net::IMAP.method(:new)
    Net::IMAP.define_singleton_method(:new) do |_host, **_kwargs|
      raise SocketError, "boom"
    end

    assert_equal 0, @account.collect_now
  ensure
    Net::IMAP.define_singleton_method(:new, original_new)
  end
end
