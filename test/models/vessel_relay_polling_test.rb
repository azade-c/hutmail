require "test_helper"
require "net/imap"

class VesselRelayPollingTest < ActiveSupport::TestCase
  FakeEnvelope = Struct.new(:message_id)
  FakeFetch = Struct.new(:attr)

  setup do
    @vessel = vessels(:one)
  end

  test "poll_relay_now skips already processed messages" do
    @vessel.processed_relay_messages.create!(imap_message_id: "old-cmd@sailmail.com")

    old_cmd = <<~MAIL
      From: #{@vessel.sailmail_address}
      To: relay@example.com
      Subject: Old commands
      Date: Mon, 08 Mar 2026 10:00:00 +0000

      ===CMD===
      STATUS
      ===END===
    MAIL

    new_cmd = <<~MAIL
      From: #{@vessel.sailmail_address}
      To: relay@example.com
      Subject: New commands
      Date: Mon, 08 Mar 2026 11:00:00 +0000

      ===CMD===
      STATUS
      ===END===
    MAIL

    stored_uids = []

    fake_imap = Object.new
    fake_imap.define_singleton_method(:login) { |_u, _p| true }
    fake_imap.define_singleton_method(:select) { |_box| true }
    fake_imap.define_singleton_method(:search) { |_query| [ 1, 2 ] }
    fake_imap.define_singleton_method(:fetch) do |uid, _attrs|
      if uid == 1
        [ FakeFetch.new({ "ENVELOPE" => FakeEnvelope.new("old-cmd@sailmail.com"), "BODY[]" => old_cmd }) ]
      else
        [ FakeFetch.new({ "ENVELOPE" => FakeEnvelope.new("new-cmd@sailmail.com"), "BODY[]" => new_cmd }) ]
      end
    end
    fake_imap.define_singleton_method(:store) { |uid, *_args| stored_uids << uid }
    fake_imap.define_singleton_method(:logout) { true }
    fake_imap.define_singleton_method(:disconnect) { true }

    original_new = Net::IMAP.method(:new)
    Net::IMAP.define_singleton_method(:new) do |_host, **_kwargs|
      fake_imap
    end

    @vessel.poll_relay_now

    assert @vessel.processed_relay_messages.exists?(imap_message_id: "new-cmd@sailmail.com")
    assert_equal 2, @vessel.processed_relay_messages.count
    assert_equal [ 2 ], stored_uids
  ensure
    Net::IMAP.define_singleton_method(:new, original_new)
  end

  test "poll_relay_now processes commands from new messages" do
    pending_msg = mail_accounts(:gmail).collected_messages.create!(
      imap_uid: 200,
      imap_message_id: "test-pending@example.com",
      from_address: "someone@example.com",
      status: "pending",
      date: Time.current,
      collected_at: Time.current,
      raw_size: 100,
      stripped_size: 50
    )

    cmd_mail = <<~MAIL
      From: #{@vessel.sailmail_address}
      To: relay@example.com
      Subject: Commands
      Date: Mon, 08 Mar 2026 10:00:00 +0000

      ===CMD===
      STATUS
      ===END===
    MAIL

    fake_imap = Object.new
    fake_imap.define_singleton_method(:login) { |_u, _p| true }
    fake_imap.define_singleton_method(:select) { |_box| true }
    fake_imap.define_singleton_method(:search) { |_query| [ 1 ] }
    fake_imap.define_singleton_method(:fetch) do |_uid, _attrs|
      [ FakeFetch.new({ "ENVELOPE" => FakeEnvelope.new("cmd-123@sailmail.com"), "BODY[]" => cmd_mail }) ]
    end
    fake_imap.define_singleton_method(:store) { |_uid, *_args| true }
    fake_imap.define_singleton_method(:logout) { true }
    fake_imap.define_singleton_method(:disconnect) { true }

    original_new = Net::IMAP.method(:new)
    Net::IMAP.define_singleton_method(:new) do |_host, **_kwargs|
      fake_imap
    end

    @vessel.poll_relay_now

    assert @vessel.processed_relay_messages.exists?(imap_message_id: "cmd-123@sailmail.com")
  ensure
    Net::IMAP.define_singleton_method(:new, original_new)
  end
end
