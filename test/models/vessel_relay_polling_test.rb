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

  # ------------------------------------------------------------------
  # Sender check — the From: has to be the vessel's own address
  # ------------------------------------------------------------------

  # IMAP SEARCH FROM matches substrings, so this message comes back from the
  # server even though it is not from the boat.
  test "poll_relay_now refuses a From: that merely contains the sailmail address" do
    lookalike = mail_with_body("POSREPORT 2026-11-05 1430 12.5S 38.5W", "",
      from: "#{@vessel.sailmail_address}.attacker.tld")

    fake_imap = build_relay_fake_imap(
      uid_search: [ 31 ],
      uid_fetch: { 31 => fake_fetch("forged@attacker.tld", lookalike) }
    )

    archived_uids = nil

    assert_no_difference [ "@vessel.position_reports.count", "@vessel.command_responses.count" ] do
      archived_uids = capture_archive_calls do
        with_fake_imap(fake_imap) { @vessel.poll_relay_now }
      end
    end

    assert_empty archived_uids
    assert_not @vessel.processed_relay_messages.exists?(imap_message_id: "forged@attacker.tld")
  end

  # One forged co-author would otherwise be enough to get a command executed.
  test "poll_relay_now refuses a From: carrying a second address alongside the vessel" do
    co_signed = mail_with_body("POSREPORT 2026-11-05 1430 12.5S 38.5W", "",
      from: "#{@vessel.sailmail_address}, evil@attacker.tld")

    fake_imap = build_relay_fake_imap(
      uid_search: [ 32 ],
      uid_fetch: { 32 => fake_fetch("co-signed@attacker.tld", co_signed) }
    )

    assert_no_difference "@vessel.position_reports.count" do
      with_fake_imap(fake_imap) { @vessel.poll_relay_now }
    end
  end

  # A display name and shouty capitals are how real mail clients write it.
  test "poll_relay_now accepts the vessel address behind a display name and in any case" do
    dressed_up = mail_with_body("POSREPORT 2026-11-05 1430 12.5S 38.5W", "",
      from: "Alibi <#{@vessel.sailmail_address.upcase}>")

    fake_imap = build_relay_fake_imap(
      uid_search: [ 33 ],
      uid_fetch: { 33 => fake_fetch("real@sailmail.com", dressed_up) }
    )

    assert_difference "@vessel.position_reports.count", 1 do
      with_fake_imap(fake_imap) { @vessel.poll_relay_now }
    end
  end

  # A refused message stays in the INBOX rather than being filed with the boat's
  # own mail, so that whoever looks at the mailbox can still see what arrived.
  test "poll_relay_now still archives the genuine messages of a mixed batch" do
    genuine = mail_with_body("Commands", "===CMD===\nSTATUS\n===END===\n")
    forged = mail_with_body("Commands", "===CMD===\nSTATUS\n===END===\n",
      from: "#{@vessel.sailmail_address}.attacker.tld")

    fake_imap = build_relay_fake_imap(
      uid_search: [ 41, 42 ],
      uid_fetch: {
        41 => fake_fetch("forged-mixed@attacker.tld", forged),
        42 => fake_fetch("genuine-mixed@sailmail.com", genuine)
      }
    )

    archived_uids = capture_archive_calls do
      with_fake_imap(fake_imap) { @vessel.poll_relay_now }
    end

    assert_equal [ 42 ], archived_uids
    assert_equal [ "genuine-mixed@sailmail.com" ], @vessel.processed_relay_messages.pluck(:imap_message_id)
  end

  private
    def mail_with_body(subject, body, from: @vessel.sailmail_address)
      <<~MAIL
        From: #{from}
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
