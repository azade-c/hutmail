require "test_helper"
require "net/imap"

class VesselRelayPollingTest < ActiveSupport::TestCase
  FakeEnvelope = Struct.new(:message_id)
  FakeFetch = Struct.new(:attr)

  setup do
    @vessel = vessels(:one)
  end

  test "poll_relay_now skips already-processed messages and archives only newly processed ones" do
    @vessel.processed_relay_messages.create!(imap_message_id: "old-cmd@sailmail.com")

    old_cmd = mail_with_body("Old commands", "===CMD===\nSTATUS\n===END===\n")
    new_cmd = mail_with_body("New commands", "===CMD===\nSTATUS\n===END===\n")

    fake_imap = build_relay_fake_imap(
      uid_search: [ 11, 22 ],
      uid_fetch: {
        11 => fake_fetch("old-cmd@sailmail.com", old_cmd),
        22 => fake_fetch("new-cmd@sailmail.com", new_cmd)
      }
    )

    archived_uids = capture_archive_calls do
      with_fake_imap(fake_imap) { @vessel.poll_relay_now }
    end

    assert @vessel.processed_relay_messages.exists?(imap_message_id: "new-cmd@sailmail.com")
    assert_equal 2, @vessel.processed_relay_messages.count
    assert_equal [ 22 ], archived_uids, "only the newly-processed uid should be archived"
  end

  test "RelayAccount::PROCESSED_FOLDER points at Hutmail/vessel" do
    assert_equal "Hutmail/vessel", RelayAccount::PROCESSED_FOLDER
  end

  test "poll_relay_now still records processed_relay_messages when archive step fails" do
    cmd_mail = mail_with_body("Commands", "===CMD===\nSTATUS\n===END===\n")

    fake_imap = build_relay_fake_imap(
      uid_search: [ 7 ],
      uid_fetch: { 7 => fake_fetch("cmd-xyz@sailmail.com", cmd_mail) }
    )

    stub_archive_with_error do
      with_fake_imap(fake_imap) do
        assert_nothing_raised { @vessel.poll_relay_now }
      end
    end

    assert @vessel.processed_relay_messages.exists?(imap_message_id: "cmd-xyz@sailmail.com")
  end

  private
    def mail_with_body(subject, body)
      <<~MAIL
        From: #{@vessel.sailmail_address}
        To: relay@example.com
        Subject: #{subject}
        Date: Mon, 08 Mar 2026 10:00:00 +0000

        #{body}
      MAIL
    end

    def fake_fetch(message_id, raw)
      FakeFetch.new({ "ENVELOPE" => FakeEnvelope.new(message_id), "BODY[]" => raw })
    end

    def build_relay_fake_imap(uid_search:, uid_fetch:)
      fake = Object.new
      fake.define_singleton_method(:login) { |_u, _p| true }
      fake.define_singleton_method(:authenticate) { |_mech, _u, _p| true }
      fake.define_singleton_method(:select) { |_box| true }
      fake.define_singleton_method(:uid_search) { |_query| uid_search }
      fake.define_singleton_method(:uid_fetch) { |uid, _attrs| [ uid_fetch[uid] ].compact }
      fake.define_singleton_method(:logout) { true }
      fake.define_singleton_method(:disconnect) { true }
      fake
    end

    def with_fake_imap(fake_imap)
      original_new = Net::IMAP.method(:new)
      Net::IMAP.define_singleton_method(:new) { |_host, **_kwargs| fake_imap }
      yield
    ensure
      Net::IMAP.define_singleton_method(:new, original_new)
    end

    def capture_archive_calls
      archived_uids = []
      original = RelayAccount.instance_method(:mark_as_processed)
      RelayAccount.define_method(:mark_as_processed) { |uids| archived_uids.concat(uids) }
      yield
      archived_uids
    ensure
      RelayAccount.define_method(:mark_as_processed, original)
    end

    def stub_archive_with_error
      original = RelayAccount.instance_method(:mark_as_processed)
      RelayAccount.define_method(:mark_as_processed) { |_uids| raise "imap blew up" }
      yield
    ensure
      RelayAccount.define_method(:mark_as_processed, original)
    end
end
