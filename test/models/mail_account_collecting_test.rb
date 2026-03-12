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

  test "collect_now fetches unseen messages, keeps known ones, and stores attachments metadata" do
    existing = @account.message_digests.create!(
      imap_uid: 555,
      imap_message_id: "dup@example.com",
      from_address: "dup@example.com",
      status: :collected,
      date: Time.current,
      collected_at: 1.hour.ago,
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

    with_fake_imap(
      search: [ 1, 2 ],
      fetches: {
        1 => { "ENVELOPE" => FakeEnvelope.new("dup@example.com"), "BODY[]" => raw_mail, "RFC822.SIZE" => raw_mail.bytesize },
        2 => { "ENVELOPE" => FakeEnvelope.new("new@example.com"), "BODY[]" => raw_mail, "RFC822.SIZE" => raw_mail.bytesize }
      }
    ) do
      count = @account.collect_now
      assert_equal 2, count
    end

    existing.reload
    assert_equal 1, existing.imap_uid
    assert existing.collected?

    msg = @account.message_digests.find_by!(imap_message_id: "new@example.com")
    assert_equal "collected", msg.status
    assert_equal "Hello crew", msg.stripped_body
    assert_equal 1, msg.attachments_metadata.size
    assert_equal "note.txt", msg.attachments_metadata.first["name"]
    assert_equal false, msg.attachments_metadata.first["inline"]
  end

  test "collect_now skips messages from sailmail address" do
    relay_mail = <<~MAIL
      From: #{@account.vessel.sailmail_address}
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

    with_fake_imap(
      search: [ 1, 2 ],
      fetches: {
        1 => { "ENVELOPE" => FakeEnvelope.new("relay-cmd@sailmail.com"), "BODY[]" => relay_mail, "RFC822.SIZE" => relay_mail.bytesize },
        2 => { "ENVELOPE" => FakeEnvelope.new("friend-msg@example.com"), "BODY[]" => normal_mail, "RFC822.SIZE" => normal_mail.bytesize }
      }
    ) do
      count = @account.collect_now
      assert_equal 1, count
    end

    assert_not @account.message_digests.exists?(imap_message_id: "relay-cmd@sailmail.com")
    assert @account.message_digests.exists?(imap_message_id: "friend-msg@example.com")
  end

  test "recollect! marks missing collected messages as no longer collectable" do
    message = @account.message_digests.create!(
      imap_uid: 700,
      imap_message_id: "missing@test",
      from_address: "old@test",
      status: :collected,
      date: Time.current,
      collected_at: Time.current,
      raw_size: 100,
      stripped_body: "old body",
      stripped_size: 8
    )

    with_fake_imap(search: [], fetches: {}) do
      @account.recollect!
    end

    message.reload
    assert message.no_longer_collectable?
  end

  test "collect_now restores a no longer collectable message when it reappears" do
    message = @account.message_digests.create!(
      imap_uid: 701,
      imap_message_id: "returns@test",
      from_address: "back@test",
      status: :no_longer_collectable,
      date: Time.current,
      collected_at: 1.day.ago,
      raw_size: 100,
      stripped_body: "old body",
      stripped_size: 8
    )

    with_fake_imap(
      search: [ 1 ],
      fetches: {
        1 => { "ENVELOPE" => FakeEnvelope.new("returns@test"), "BODY[]" => nil, "RFC822.SIZE" => 0 }
      }
    ) do
      count = @account.collect_now
      assert_equal 1, count
    end

    message.reload
    assert message.collected?
    assert_equal 1, message.imap_uid
  end

  test "collect_now marks bundled messages as requeued when they reappear" do
    message = @account.message_digests.create!(
      imap_uid: 900,
      imap_message_id: "rebundle-me@example.com",
      from_address: "sender@example.com",
      status: :bundled,
      date: Time.current,
      collected_at: Time.current,
      raw_size: 100,
      stripped_size: 20
    )

    with_fake_imap(
      search: [ 1 ],
      fetches: {
        1 => { "ENVELOPE" => FakeEnvelope.new("rebundle-me@example.com"), "BODY[]" => nil, "RFC822.SIZE" => 0 }
      }
    ) do
      count = @account.collect_now
      assert_equal 1, count
    end

    message.reload
    assert message.requeued?
    assert_equal 1, message.imap_uid
  end

  test "collect_now returns missing requeued messages to bundled" do
    message = @account.message_digests.create!(
      imap_uid: 901,
      imap_message_id: "gone-again@example.com",
      from_address: "sender@example.com",
      status: :requeued,
      date: Time.current,
      collected_at: Time.current,
      raw_size: 100,
      stripped_size: 20
    )

    with_fake_imap(search: [], fetches: {}) do
      @account.collect_now
    end

    message.reload
    assert message.bundled?
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

  test "mark_as_processed marks as Seen and moves to HutMail folder" do
    stored_flags = []
    moved_to = nil
    created_folder = nil

    fake_imap = Object.new
    fake_imap.define_singleton_method(:login) { |_u, _p| true }
    fake_imap.define_singleton_method(:select) { |_box| true }
    fake_imap.define_singleton_method(:create) { |name| created_folder = name }
    fake_imap.define_singleton_method(:uid_store) { |uids, flag, vals| stored_flags << { uids:, flag:, vals: } }
    fake_imap.define_singleton_method(:uid_move) { |uids, folder| moved_to = folder }
    fake_imap.define_singleton_method(:logout) { true }
    fake_imap.define_singleton_method(:disconnect) { true }

    original_new = Net::IMAP.method(:new)
    Net::IMAP.define_singleton_method(:new) do |_host, **_kwargs|
      fake_imap
    end

    @account.mark_as_processed([ 42, 43 ])

    assert_equal "HutMail", created_folder
    assert_equal 1, stored_flags.size
    assert_equal "+FLAGS", stored_flags.first[:flag]
    assert_includes stored_flags.first[:vals], :Seen
    assert_equal "HutMail", moved_to
  ensure
    Net::IMAP.define_singleton_method(:new, original_new)
  end

  test "mark_as_processed does nothing when uids list is empty" do
    assert_nil @account.mark_as_processed([])
  end

  private
    def with_fake_imap(search:, fetches:)
      fake_imap = Object.new
      fake_imap.define_singleton_method(:login) { |_u, _p| true }
      fake_imap.define_singleton_method(:select) { |_box| true }
      fake_imap.define_singleton_method(:uid_search) { |_query| search }
      fake_imap.define_singleton_method(:uid_fetch) do |uid, _attrs|
        data = fetches[uid]
        data ? [ FakeFetch.new(data) ] : nil
      end
      fake_imap.define_singleton_method(:logout) { true }
      fake_imap.define_singleton_method(:disconnect) { true }

      original_new = Net::IMAP.method(:new)
      Net::IMAP.define_singleton_method(:new) do |_host, **_kwargs|
        fake_imap
      end

      yield
    ensure
      Net::IMAP.define_singleton_method(:new, original_new)
    end
end
