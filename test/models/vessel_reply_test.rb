require "test_helper"

class VesselReplyTest < ActiveSupport::TestCase
  setup do
    @vessel = vessels(:one)
    @account = mail_accounts(:gmail)
  end

  test "deliver_now captures the outbound Message-ID" do
    reply = VesselReply.create!(
      vessel: @vessel, mail_account: @account, message_digest: nil,
      to_address: "alice@example.com", subject: "Hi", body: "hello", status: "pending"
    )

    outbound = Object.new
    outbound.define_singleton_method(:deliver_now) { true }
    outbound.define_singleton_method(:message_id) { "captured-reply-id@hutmail.example" }

    original_send_reply = OutboundMailer.method(:send_reply)
    OutboundMailer.define_singleton_method(:send_reply) do |_reply, **_opts|
      outbound
    end

    reply.deliver_now

    reply.reload
    assert_equal "sent", reply.status
    assert_equal "<captured-reply-id@hutmail.example>", reply.outbound_message_id,
      "outbound_message_id must be stored in bracketed canonical form to match IMAP envelopes"
  ensure
    OutboundMailer.define_singleton_method(:send_reply, original_send_reply)
  end

  test "deliver_now wraps an already-bracketed Message-ID without doubling brackets" do
    reply = VesselReply.create!(
      vessel: @vessel, mail_account: @account, message_digest: nil,
      to_address: "alice@example.com", subject: "Hi", body: "hello", status: "pending"
    )

    outbound = Object.new
    outbound.define_singleton_method(:deliver_now) { true }
    outbound.define_singleton_method(:message_id) { "<already-wrapped@hutmail.example>" }

    original_send_reply = OutboundMailer.method(:send_reply)
    OutboundMailer.define_singleton_method(:send_reply) do |_reply, **_opts|
      outbound
    end

    reply.deliver_now

    assert_equal "<already-wrapped@hutmail.example>", reply.reload.outbound_message_id
  ensure
    OutboundMailer.define_singleton_method(:send_reply, original_send_reply)
  end
end
