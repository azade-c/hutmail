require "test_helper"
require "net/imap"

# End-to-end coverage stitching together the full chains shipped in
# PR #76 (scheduled bundling) and PR #77 (command-response routing).
#
# Strategy: stub only the leaf I/O surfaces (IMAP, SMTP-delivering
# mailers, sent-folder appends, message collection). Everything in
# between — recurring tick, dispatch job, command parser, bundle
# composer, response mailer plumbing — runs for real.
class SchedulingAndCommandsE2ETest < ActiveJob::TestCase
  FakeEnvelope = Struct.new(:message_id)
  FakeFetch = Struct.new(:attr)

  setup do
    @vessel = vessels(:one)
    @account = mail_accounts(:gmail)
    @delivered_bundles = []
    @delivered_responses = []
    @appended_to_sent = []
    @marked_processed = []
    @collect_calls = []
  end

  teardown do
    restore_stubs!
  end

  # ---------------------------------------------------------------------------
  # A. Scheduled bundling E2E
  # ---------------------------------------------------------------------------

  test "every_hours cadence: tick -> dispatch job -> collect+compose+deliver -> reschedule" do
    stub_collect_noop!
    stub_relay_mailer!
    stub_append_and_mark_processed!

    travel_to Time.utc(2026, 5, 23, 12, 0, 0) do
      @vessel.update!(
        dispatch_cadence: "every_hours",
        dispatch_every_hours: 2,
        last_dispatched_at: Time.utc(2026, 5, 23, 9, 0, 0)
      )
      # next_dispatch_at recomputed to 11:00, which is past 12:00 -> due
      assert @vessel.reload.next_dispatch_at <= Time.current

      perform_enqueued_jobs do
        DispatchDueVesselsJob.perform_now
      end

      assert_equal @vessel.mail_accounts.count, @collect_calls.size,
        "collect_now should be invoked once per vessel mail account"
      assert_equal 1, @delivered_bundles.size, "exactly one bundle should be delivered"
      assert_equal 1, @appended_to_sent.size, "the delivered bundle should be appended to relay Sent folder"

      bundle = @vessel.bundles.order(:id).last
      assert_equal "sent", bundle.status
      assert bundle.messages_count.positive?, "fixtures provide collected messages so bundle should be non-empty"

      @vessel.reload
      assert_in_delta Time.current.to_i, @vessel.last_dispatched_at.to_i, 5
      assert_in_delta (Time.current + 2.hours).to_i, @vessel.next_dispatch_at.to_i, 5
    end
  end

  test "daily cadence: tick at due time triggers dispatch and rolls schedule to next day" do
    stub_collect_noop!
    stub_relay_mailer!
    stub_append_and_mark_processed!

    travel_to Time.utc(2026, 5, 23, 9, 30, 0) do
      @vessel.update!(
        dispatch_cadence: "daily",
        dispatch_daily_at: "09:30",
        dispatch_timezone: "UTC"
      )
      # update! validation triggers compute_next_dispatch_at; since candidate
      # equals "now", it rolls to tomorrow. Force the row past-due so the
      # recurring tick will pick it up this run.
      @vessel.update_columns(next_dispatch_at: Time.utc(2026, 5, 23, 9, 29, 0))

      perform_enqueued_jobs do
        DispatchDueVesselsJob.perform_now
      end

      assert_equal 1, @delivered_bundles.size
      @vessel.reload
      assert_equal Time.utc(2026, 5, 24, 9, 30, 0), @vessel.next_dispatch_at,
        "daily cadence should re-target tomorrow at the configured time"
    end
  end

  test "manual cadence: tick does not enqueue Vessel::DispatchJob" do
    @vessel.update!(dispatch_cadence: "manual")
    assert_nil @vessel.next_dispatch_at

    assert_no_enqueued_jobs only: Vessel::DispatchJob do
      DispatchDueVesselsJob.perform_now
    end
  end

  # ---------------------------------------------------------------------------
  # B. Subject command E2E (RelayPollJob -> CommandResponse delivered)
  # ---------------------------------------------------------------------------

  test "subject PING: poll -> parse -> CommandResponse.sent with PONG payload" do
    stub_command_response_mailer!
    stub_append_for_command_responses!
    stub_relay_imap_with(uid: 11, message_id: "ping-1@sailmail.com",
                         subject: "PING", body: "ignored body\n")

    perform_enqueued_jobs do
      RelayPollJob.perform_now
    end

    cr = @vessel.command_responses.order(:id).last
    assert_equal "subject", cr.source
    assert_equal "PING", cr.command
    assert_equal "sent", cr.status
    assert_not_nil cr.sent_at
    assert_match(/\APONG \d{4}-\d{2}-\d{2}T\d{2}:\d{2}Z hutmail\z/, cr.response_text)

    assert_equal 1, @delivered_responses.size
    delivered = @delivered_responses.first
    assert_equal cr, delivered[:command_response]
  end

  test "subject STATUS and Re: STATUS both produce STATUS responses" do
    stub_command_response_mailer!
    stub_append_for_command_responses!
    stub_relay_imap_multi(
      11 => { message_id: "s1@sm", subject: "STATUS",        body: "\n" },
      12 => { message_id: "s2@sm", subject: "Re: STATUS",    body: "\n" }
    )

    perform_enqueued_jobs do
      RelayPollJob.perform_now
    end

    crs = @vessel.command_responses.order(:id).last(2)
    assert_equal [ "STATUS", "STATUS" ], crs.map(&:command)
    assert crs.all? { |cr| cr.source == "subject" && cr.status == "sent" }
    assert crs.all? { |cr| cr.response_text.start_with?("STATUS hutmail") }
  end

  test "subject HELP returns help text" do
    stub_command_response_mailer!
    stub_append_for_command_responses!
    stub_relay_imap_with(uid: 99, message_id: "h@sm", subject: "HELP", body: "\n")

    perform_enqueued_jobs do
      RelayPollJob.perform_now
    end

    cr = @vessel.command_responses.order(:id).last
    assert_equal "HELP", cr.command
    assert_equal "sent", cr.status
    assert_match(/HUTMAIL commands/, cr.response_text)
  end

  # ---------------------------------------------------------------------------
  # C. Body command E2E (deferred, folded into next bundle)
  # ---------------------------------------------------------------------------

  test "body STATUS: queued pending, then folded into next scheduled bundle" do
    stub_command_response_mailer!
    stub_append_for_command_responses!
    stub_relay_imap_with(
      uid: 21, message_id: "body-status@sm",
      subject: "Bonjour bateau",
      body: "===CMD===\nSTATUS\n===END===\n"
    )

    # 1) Poll inbound -> body command queued, no immediate delivery.
    assert_no_enqueued_jobs only: CommandResponse::DeliverJob do
      perform_enqueued_jobs do
        RelayPollJob.perform_now
      end
    end

    cr = @vessel.command_responses.order(:id).last
    assert_equal "body", cr.source
    assert_equal "STATUS", cr.command
    assert_equal "pending", cr.status
    assert_nil cr.bundle_id
    assert_equal 0, @delivered_responses.size

    # 2) Next scheduled dispatch picks it up and folds it into the bundle.
    stub_collect_noop!
    stub_relay_mailer!
    stub_append_and_mark_processed!

    travel_to Time.utc(2026, 5, 23, 12, 0, 0) do
      @vessel.update!(dispatch_cadence: "every_hours", dispatch_every_hours: 1)
      @vessel.update_columns(next_dispatch_at: 1.minute.ago)

      perform_enqueued_jobs do
        DispatchDueVesselsJob.perform_now
      end
    end

    bundle = @vessel.bundles.order(:id).last
    assert_equal "sent", bundle.status
    assert_match(/STATUS response/, bundle.bundle_text)
    assert_match(/STATUS hutmail/, bundle.bundle_text)

    response_pos = bundle.bundle_text.index("STATUS response")
    first_account_pos = bundle.bundle_text.index("==[ GM")
    assert response_pos && first_account_pos && response_pos < first_account_pos,
      "command response block should appear before account sections"

    cr.reload
    assert_equal "included", cr.status
    assert_equal bundle, cr.bundle
  end

  # ---------------------------------------------------------------------------
  # D. Mixed: subject + body in same inbound message
  # ---------------------------------------------------------------------------

  test "subject PING + body STATUS: subject answered immediately, body queued for next bundle" do
    stub_command_response_mailer!
    stub_append_for_command_responses!
    stub_relay_imap_with(
      uid: 31, message_id: "mixed@sm",
      subject: "PING",
      body: "===CMD===\nSTATUS\n===END===\n"
    )

    perform_enqueued_jobs do
      RelayPollJob.perform_now
    end

    subject_cr = @vessel.command_responses.where(source: "subject").order(:id).last
    body_cr    = @vessel.command_responses.where(source: "body").order(:id).last

    assert_equal "PING",   subject_cr.command
    assert_equal "sent",   subject_cr.status
    assert_match(/\APONG /, subject_cr.response_text)

    assert_equal "STATUS",  body_cr.command
    assert_equal "pending", body_cr.status
    assert_nil body_cr.bundle_id

    assert_equal 1, @delivered_responses.size,
      "only the subject command should have been delivered immediately"
  end

  # ---------------------------------------------------------------------------
  # Stub helpers
  # ---------------------------------------------------------------------------

  private
    def stub_collect_noop!
      @orig_collect_now = MailAccount.instance_method(:collect_now)
      capture = @collect_calls
      MailAccount.define_method(:collect_now) do
        capture << id
        0
      end
    end

    def stub_relay_mailer!
      @orig_send_bundle = RelayMailer.method(:send_bundle)
      delivered = @delivered_bundles
      RelayMailer.define_singleton_method(:send_bundle) do |bundle, **_opts|
        fake = Object.new
        fake.define_singleton_method(:deliver_now) { delivered << bundle; true }
        fake.define_singleton_method(:message_id)  { "bundle-#{bundle.object_id}@hutmail.test" }
        fake.define_singleton_method(:message)     { Mail.new("Subject: test\n\nhi") }
        fake
      end
    end

    def stub_command_response_mailer!
      # CommandResponse#deliver_now goes through deliver_with_auth_fallback,
      # whose block invokes the class-level CommandResponseMailer.send_response
      # (returning what is normally an ActionMailer::MessageDelivery). Stub at
      # the class level so .deliver_now on our fake is what runs.
      @orig_send_response = CommandResponseMailer.method(:send_response)
      delivered = @delivered_responses
      CommandResponseMailer.define_singleton_method(:send_response) do |command_response, auth_method: nil|
        fake = Object.new
        fake.define_singleton_method(:deliver_now) do
          delivered << { command_response: command_response, auth_method: auth_method }
          true
        end
        fake.define_singleton_method(:message_id) { "cr-#{command_response.id}@hutmail.test" }
        fake.define_singleton_method(:message)    { Mail.new("Subject: HUTMAIL #{command_response.command}\n\n#{command_response.response_text}") }
        fake
      end
    end

    def stub_append_and_mark_processed!
      @orig_append = RelayAccount.instance_method(:append_to_sent)
      @orig_mark   = MailAccount.instance_method(:mark_as_processed)
      appended = @appended_to_sent
      marked   = @marked_processed
      RelayAccount.define_method(:append_to_sent) { |raw| appended << raw; "Sent" }
      MailAccount.define_method(:mark_as_processed) { |uids| marked << { account_id: id, uids: uids }; true }
    end

    def stub_append_for_command_responses!
      # CommandResponse#deliver_now appends to relay Sent folder on success.
      @orig_append_cr = RelayAccount.instance_method(:append_to_sent)
      appended = @appended_to_sent
      RelayAccount.define_method(:append_to_sent) { |raw| appended << raw; "Sent" }
    end

    def stub_relay_imap_with(uid:, message_id:, subject:, body:)
      stub_relay_imap_multi(uid => { message_id: message_id, subject: subject, body: body })
    end

    def stub_relay_imap_multi(uid_map)
      vessel_from = @vessel.sailmail_address
      raw_by_uid = uid_map.transform_values do |spec|
        <<~MAIL
          From: #{vessel_from}
          To: relay@example.com
          Subject: #{spec[:subject]}
          Message-ID: <#{spec[:message_id]}>
          Date: Mon, 08 Mar 2026 10:00:00 +0000

          #{spec[:body]}
        MAIL
      end

      fake = Object.new
      fake.define_singleton_method(:login)        { |_u, _p| true }
      fake.define_singleton_method(:authenticate) { |_m, _u, _p| true }
      fake.define_singleton_method(:select)       { |_box| true }
      fake.define_singleton_method(:uid_search)   { |_q| uid_map.keys }
      fake.define_singleton_method(:uid_fetch) do |uid, _attrs|
        raw = raw_by_uid[uid]
        next [] unless raw
        [ FakeFetch.new({ "ENVELOPE" => FakeEnvelope.new(uid_map[uid][:message_id]), "BODY[]" => raw }) ]
      end
      fake.define_singleton_method(:logout)     { true }
      fake.define_singleton_method(:disconnect) { true }

      @orig_imap_new = Net::IMAP.method(:new)
      Net::IMAP.define_singleton_method(:new) { |_host, **_kwargs| fake }
      # Also stub mark_as_processed on RelayAccount so the post-poll archive
      # step doesn't blow up when no real IMAP is available.
      @orig_relay_mark_as_processed = RelayAccount.instance_method(:mark_as_processed)
      RelayAccount.define_method(:mark_as_processed) { |_uids| true }
    end

    def restore_stubs!
      MailAccount.define_method(:collect_now, @orig_collect_now)          if @orig_collect_now
      RelayMailer.define_singleton_method(:send_bundle, @orig_send_bundle) if @orig_send_bundle
      CommandResponseMailer.define_singleton_method(:send_response, @orig_send_response) if @orig_send_response
      RelayAccount.define_method(:append_to_sent, @orig_append)            if @orig_append
      MailAccount.define_method(:mark_as_processed, @orig_mark)            if @orig_mark
      RelayAccount.define_method(:append_to_sent, @orig_append_cr)         if @orig_append_cr && !@orig_append
      RelayAccount.define_method(:mark_as_processed, @orig_relay_mark_as_processed) if @orig_relay_mark_as_processed
      Net::IMAP.define_singleton_method(:new, @orig_imap_new)              if @orig_imap_new
    end
end
