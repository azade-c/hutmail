require "test_helper"

class VesselReplyDeliverJobTest < ActiveJob::TestCase
  setup do
    @vessel = vessels(:one)
    @account = mail_accounts(:gmail)
  end

  test "marks reply as sent on successful delivery" do
    reply = @vessel.vessel_replies.create!(
      mail_account: @account,
      to_address: "bob@example.com",
      body: "hello",
      status: "pending"
    )

    delivered = false
    outbound = Object.new
    outbound.define_singleton_method(:deliver_now) { delivered = true }

    original_send_reply = OutboundMailer.method(:send_reply)
    OutboundMailer.define_singleton_method(:send_reply) do |_reply, **_opts|
      outbound
    end

    VesselReply::DeliverJob.perform_now(reply)

    reply.reload
    assert delivered
    assert_equal "sent", reply.status
    assert_not_nil reply.sent_at
  ensure
    OutboundMailer.define_singleton_method(:send_reply, original_send_reply)
  end

  test "marks reply as error on failed delivery" do
    reply = @vessel.vessel_replies.create!(
      mail_account: @account,
      to_address: "bob@example.com",
      body: "hello",
      status: "pending"
    )

    outbound = Object.new
    outbound.define_singleton_method(:deliver_now) { raise "smtp down" }

    original_send_reply = OutboundMailer.method(:send_reply)
    OutboundMailer.define_singleton_method(:send_reply) do |_reply, **_opts|
      outbound
    end

    VesselReply::DeliverJob.perform_now(reply)

    reply.reload
    assert_equal "error", reply.status
    assert_includes reply.error_message, "smtp down"
  ensure
    OutboundMailer.define_singleton_method(:send_reply, original_send_reply)
  end
end
