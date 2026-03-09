require "test_helper"

class VesselBundlingTest < ActiveSupport::TestCase
  setup do
    @vessel = vessels(:one)
    @account = mail_accounts(:gmail)
  end

  test "build_and_deliver_bundle sends included messages and keeps remaining pending" do
    @vessel.update!(daily_budget_kb: 1, bundle_ratio: 50)
    @account.collected_messages.delete_all

    created = 3.times.map do |i|
      @account.collected_messages.create!(
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
        status: "pending",
        collected_at: Time.current
      )
    end

    delivered = false
    relay_message = Object.new
    relay_message.define_singleton_method(:deliver_now) { delivered = true }

    calls = []
    original_mark_as_read = MailAccount.instance_method(:mark_as_read)
    MailAccount.define_method(:mark_as_read) do |imap_uids|
      calls << { id: id, uids: imap_uids }
      true
    end

    original_send_bundle = RelayMailer.method(:send_bundle)
    RelayMailer.define_singleton_method(:send_bundle) do |_bundle|
      relay_message
    end

    bundle = @vessel.build_and_deliver_bundle

    assert delivered
    assert_equal "sent", bundle.status
    assert_equal 1, bundle.messages_count
    assert_equal 2, bundle.remaining_count

    sent = CollectedMessage.where(bundle_id: bundle.id, status: "sent")
    assert_equal 1, sent.count
    assert_equal 2, CollectedMessage.where(id: created.map(&:id), status: "pending").count

    assert_equal 1, calls.size
    assert_equal [ sent.first.imap_uid ], calls.first[:uids]
  ensure
    MailAccount.define_method(:mark_as_read, original_mark_as_read)
    RelayMailer.define_singleton_method(:send_bundle, original_send_bundle)
  end

  test "deliver_bundle marks bundle as error when mailer raises" do
    bundle = @vessel.bundles.create!(status: "draft")

    failing_relay = Object.new
    failing_relay.define_singleton_method(:deliver_now) { raise "smtp failed" }

    original_send_bundle = RelayMailer.method(:send_bundle)
    RelayMailer.define_singleton_method(:send_bundle) do |_bundle|
      failing_relay
    end

    @vessel.deliver_bundle(bundle)

    bundle.reload
    assert_equal "error", bundle.status
    assert_includes bundle.error_message, "smtp failed"
  ensure
    RelayMailer.define_singleton_method(:send_bundle, original_send_bundle)
  end
end
