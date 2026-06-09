require "test_helper"

class VesselDispatchingTest < ActiveSupport::TestCase
  setup do
    @vessel = vessels(:one)
    @account = mail_accounts(:gmail)
  end

  test "dispatch_now sends included messages and keeps remaining collected" do
    @vessel.update!(daily_budget_kb: 1, bundle_ratio: 50)
    @account.message_digests.delete_all

    created = 3.times.map do |i|
      @account.message_digests.create!(
        imap_uid: 200 + i,
        imap_message_id: "bundle#{i}@example.com",
        from_address: "sender#{i}@example.com",
        from_name: "Sender #{i}",
        to_address: "crew@example.com",
        subject: "Subject #{i}",
        date: Time.current + i.minutes,
        raw_size: 3000,
        stripped_body: "Body #{i}",
        stripped_size: 2000,
        status: :collected,
        collected_at: Time.current
      )
    end

    delivered = false
    relay_message = Object.new
    relay_message.define_singleton_method(:deliver_now) { delivered = true }
    relay_message.define_singleton_method(:message_id) { nil }
    relay_message.define_singleton_method(:message) { Mail.new("Subject: test\n\nhello") }

    appended_messages = []
    processed_calls = []
    original_append_to_sent = RelayAccount.instance_method(:append_to_sent)
    RelayAccount.define_method(:append_to_sent) do |raw_message|
      appended_messages << raw_message
      "Sent"
    end

    original_mark_as_processed = MailAccount.instance_method(:mark_as_processed)
    MailAccount.define_method(:mark_as_processed) do |imap_uids|
      processed_calls << { id: id, uids: imap_uids }
      true
    end

    original_send_bundle = RelayMailer.method(:send_bundle)
    RelayMailer.define_singleton_method(:send_bundle) do |_bundle, **_opts|
      relay_message
    end

    bundle = @vessel.dispatch_now

    assert delivered
    assert_equal 1, appended_messages.size
    assert_equal "sent", bundle.status
    assert_equal 1, bundle.messages_count
    assert_equal 2, bundle.remaining_count

    bundled_digests = bundle.message_digests.where(status: MessageDigest.statuses.fetch("bundled"))
    assert_equal 1, bundled_digests.count
    assert_equal 2, MessageDigest.where(id: created.map(&:id), status: MessageDigest.statuses.fetch("collected")).count

    assert_equal 1, processed_calls.size
    assert_equal [ bundled_digests.first.imap_uid ], processed_calls.first[:uids]
  ensure
    RelayAccount.define_method(:append_to_sent, original_append_to_sent)
    MailAccount.define_method(:mark_as_processed, original_mark_as_processed)
    RelayMailer.define_singleton_method(:send_bundle, original_send_bundle)
  end

  test "deliver_now captures the outbound Message-ID on the bundle" do
    bundle = @vessel.bundles.create!(status: "draft")

    relay_message = Object.new
    relay_message.define_singleton_method(:deliver_now) { true }
    relay_message.define_singleton_method(:message_id) { "captured-bundle-id@hutmail.example" }
    relay_message.define_singleton_method(:message) { Mail.new("Subject: test\n\nhi") }

    original_send_bundle = RelayMailer.method(:send_bundle)
    RelayMailer.define_singleton_method(:send_bundle) do |_bundle, **_opts|
      relay_message
    end

    original_append_to_sent = RelayAccount.instance_method(:append_to_sent)
    RelayAccount.define_method(:append_to_sent) { |_raw| "Sent" }

    bundle.deliver_now

    bundle.reload
    assert_equal "<captured-bundle-id@hutmail.example>", bundle.outbound_message_id,
      "outbound_message_id must be stored in bracketed canonical form to match IMAP envelopes"
  ensure
    RelayMailer.define_singleton_method(:send_bundle, original_send_bundle)
    RelayAccount.define_method(:append_to_sent, original_append_to_sent)
  end

  test "bundle deliver records error when mailer raises" do
    bundle = @vessel.bundles.create!(status: "draft")

    failing_relay = Object.new
    failing_relay.define_singleton_method(:deliver_now) { raise "smtp failed" }

    original_send_bundle = RelayMailer.method(:send_bundle)
    RelayMailer.define_singleton_method(:send_bundle) do |_bundle, **_opts|
      failing_relay
    end

    bundle.deliver_now

    bundle.reload
    assert_equal "error", bundle.status
    assert_includes bundle.error_message, "smtp failed"
  ensure
    RelayMailer.define_singleton_method(:send_bundle, original_send_bundle)
  end

  test "preview_dispatch returns non-persisted bundle with text" do
    assert @account.message_digests.bundleable.any?

    preview = @vessel.preview_dispatch

    assert preview.present?
    assert preview.new_record?
    assert_equal "preview", preview.status
    assert preview.bundle_text.include?("=== HUTMAIL")
    assert preview.bundle_text.include?("=== END ===")
    assert preview.messages_count.positive?
    assert_equal 0, Bundle.where(status: "preview").count
  end

  test "preview_dispatch returns nil when no messages are ready for bundling" do
    MessageDigest.where(
      mail_account_id: @vessel.mail_accounts.select(:id)
    ).update_all(status: MessageDigest.statuses.fetch("bundled"))

    assert_nil @vessel.preview_dispatch
  end

  test "preview_dispatch does not change message statuses" do
    bundleable_before = MessageDigest.bundleable.where(
      mail_account_id: @vessel.mail_accounts.select(:id)
    ).count

    @vessel.preview_dispatch

    bundleable_after = MessageDigest.bundleable.where(
      mail_account_id: @vessel.mail_accounts.select(:id)
    ).count
    assert_equal bundleable_before, bundleable_after
  end

  # The rolling budget must be charged the real transmitted weight of the
  # bundle (its text), not the sum of stripped bodies. A truncated dispatch
  # must cost only what actually went over the radio, and a later GET of the
  # full message must not double-charge the original body.
  test "dispatch_size reflects the truncated bundle text, not the full stripped body" do
    @account.message_digests.delete_all
    @vessel.update!(message_char_limit: 200, daily_budget_kb: 100)

    long_body = "Encyclique " * 2000 # ~22 KB stripped body
    assert_operator long_body.bytesize, :>, 20_000

    digest = @account.message_digests.create!(
      imap_uid: 7001,
      imap_message_id: "encyclique@example.test",
      from_address: "pape@example.test",
      from_name: "Le Pape",
      to_address: "crew@example.test",
      subject: "Encyclique",
      date: Time.current,
      raw_size: 30_000,
      stripped_body: long_body,
      stripped_size: long_body.bytesize,
      status: :collected,
      collected_at: Time.current
    )

    bundle = @vessel.bundles.create!(status: "draft")
    bundle.compose!([ digest ], [])

    # The transmitted weight is bounded by the char limit, far below the body.
    assert_includes bundle.bundle_text, "message tronqu\u00e9"
    assert_equal bundle.bundle_text.bytesize, bundle.dispatch_size
    assert_operator bundle.dispatch_size, :<, 2_000,
      "a truncated dispatch must not be charged the full stripped body"
    assert_operator bundle.dispatch_size, :<, digest.stripped_size,
      "transmitted weight must be smaller than the untruncated body"
  end

  test "a GET re-send is charged only its own transmitted weight, not the original body again" do
    @account.message_digests.delete_all
    @vessel.update!(message_char_limit: 200, daily_budget_kb: 100)

    long_body = "Encyclique " * 2000
    digest = @account.message_digests.create!(
      imap_uid: 7002,
      imap_message_id: "get-encyclique@example.test",
      from_address: "pape@example.test",
      from_name: "Le Pape",
      to_address: "crew@example.test",
      subject: "Encyclique",
      date: Time.current,
      raw_size: 30_000,
      stripped_body: long_body,
      stripped_size: long_body.bytesize,
      status: :collected,
      collected_at: Time.current
    )

    stub_relay_delivery

    # 1) Normal (truncated) dispatch.
    truncated = @vessel.bundles.create!(status: "draft")
    truncated.compose!([ digest ], [])
    truncated.deliver_now

    # 2) Full GET re-send (truncate: false).
    full = @vessel.dispatch_get_response([ digest.reload ])

    # The GET carries the full body, so it costs more than the truncated one…
    assert_operator full.dispatch_size, :>, truncated.dispatch_size
    # …but each bundle is charged only its own transmitted text, never the
    # abstract stripped_size, and never the body twice.
    assert_equal full.bundle_text.bytesize, full.dispatch_size
    assert_equal truncated.bundle_text.bytesize, truncated.dispatch_size

    consumed = @vessel.budget_consumed_7d
    combined_text = truncated.dispatch_size + full.dispatch_size
    assert_equal combined_text, consumed,
      "budget must sum the real transmitted weights of sent bundles"
    assert_operator consumed, :<, 2 * digest.stripped_size,
      "the body must not be double-charged across the truncated + GET pair"
  end

  # GET must transmit the full stripped text of a message but never the raw
  # bytes of attachments or inline HTML images. Attachments and inline images
  # are represented by lightweight placeholders only; the actual binary is
  # never relayed over the radio link.
  test "dispatch_get_response transmits text only, never attachment or image bytes" do
    mail = Mail.read(file_fixture("real_mail_corpus/05_inline_image_message.eml"))
    raw_size = mail.to_s.bytesize
    stripped = MessageDigest.strip_mail(mail)

    @account.message_digests.delete_all
    digest = @account.message_digests.create!(
      imap_uid: 4242,
      imap_message_id: "get-image@example.test",
      from_address: "sender@example.test",
      from_name: "Sam Sender",
      to_address: "crew@example.test",
      subject: "Message avec une image en PJ et en corps de texte",
      date: Time.current,
      raw_size: raw_size,
      stripped_body: stripped,
      stripped_size: stripped.bytesize,
      status: :collected,
      collected_at: Time.current,
      attachments_metadata: [
        { name: "photo.jpg", size: 150_800, content_type: "image/jpeg", inline: false }
      ]
    )

    sent_messages = []
    original_send_bundle = RelayMailer.method(:send_bundle)
    RelayMailer.define_singleton_method(:send_bundle) do |bundle, **_opts|
      sent_messages << bundle.bundle_text
      relay = Object.new
      relay.define_singleton_method(:deliver_now) { true }
      relay.define_singleton_method(:message_id) { nil }
      relay.define_singleton_method(:message) { Mail.new("Subject: test\n\nhi") }
      relay
    end

    original_append_to_sent = RelayAccount.instance_method(:append_to_sent)
    RelayAccount.define_method(:append_to_sent) { |_raw| "Sent" }

    original_mark_as_processed = MailAccount.instance_method(:mark_as_processed)
    MailAccount.define_method(:mark_as_processed) { |_uids| true }

    bundle = @vessel.dispatch_get_response([ digest ])

    radio_text = sent_messages.first
    assert_not_nil radio_text, "GET must produce an outbound bundle text"

    # The full stripped body is present (text is transmitted in its entirety).
    assert_includes radio_text, stripped

    # The inline image is referenced by a placeholder, not its bytes.
    assert_match(/\[image : /, radio_text)

    # The transmitted bundle is tiny: nowhere near the raw mail size.
    assert_operator bundle.bundle_text.bytesize, :<, 10_000,
      "GET payload must stay small; attachment/image bytes must not leak in"
    assert_operator bundle.bundle_text.bytesize, :<, raw_size / 10,
      "GET payload must be far smaller than the raw mail (no binary leak)"

    # No base64 attachment block and no MIME boundary should appear in the text.
    refute_match(/Content-Transfer-Encoding:\s*base64/i, radio_text)
    refute_match(/^------=_NextPart/, radio_text)
  ensure
    RelayMailer.define_singleton_method(:send_bundle, original_send_bundle) if original_send_bundle
    RelayAccount.define_method(:append_to_sent, original_append_to_sent) if original_append_to_sent
    MailAccount.define_method(:mark_as_processed, original_mark_as_processed) if original_mark_as_processed
  end

  private
    def stub_relay_delivery
      @original_send_bundle = RelayMailer.method(:send_bundle)
      RelayMailer.define_singleton_method(:send_bundle) do |_bundle, **_opts|
        relay = Object.new
        relay.define_singleton_method(:deliver_now) { true }
        relay.define_singleton_method(:message_id) { nil }
        relay.define_singleton_method(:message) { Mail.new("Subject: t\n\nx") }
        relay
      end

      @original_append_to_sent = RelayAccount.instance_method(:append_to_sent)
      RelayAccount.define_method(:append_to_sent) { |_raw| "Sent" }

      @original_mark_as_processed = MailAccount.instance_method(:mark_as_processed)
      MailAccount.define_method(:mark_as_processed) { |_uids| true }
    end

    def teardown
      RelayMailer.define_singleton_method(:send_bundle, @original_send_bundle) if @original_send_bundle
      RelayAccount.define_method(:append_to_sent, @original_append_to_sent) if @original_append_to_sent
      MailAccount.define_method(:mark_as_processed, @original_mark_as_processed) if @original_mark_as_processed
    end
end
