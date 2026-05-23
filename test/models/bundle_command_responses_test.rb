require "test_helper"

class BundleCommandResponsesTest < ActiveSupport::TestCase
  setup do
    @vessel = vessels(:one)
    @account = mail_accounts(:gmail)
  end

  test "compose! includes pending body command responses and marks them included" do
    cr = @vessel.command_responses.create!(
      source: "body",
      command: "STATUS",
      response_text: "STATUS hutmail\nready: 0 messages",
      status: "pending"
    )

    msg = @account.message_digests.create!(
      imap_uid: 999,
      imap_message_id: "x@example.com",
      from_address: "s@example.com",
      from_name: "S",
      to_address: "c@example.com",
      subject: "hi",
      date: Time.current,
      raw_size: 100,
      stripped_body: "hi",
      stripped_size: 50,
      status: :collected,
      collected_at: Time.current
    )

    bundle = @vessel.bundles.create!(status: "draft")
    bundle.compose!([ msg ], [])

    assert_match(/STATUS response/, bundle.bundle_text)
    assert_match(/STATUS hutmail/, bundle.bundle_text)

    cr.reload
    assert_equal "included", cr.status
    assert_equal bundle, cr.bundle
  end

  test "subject responses are not picked up by bundle composition" do
    @vessel.command_responses.create!(
      source: "subject",
      command: "PING",
      response_text: "PONG ...",
      status: "pending"
    )

    bundle = @vessel.bundles.create!(status: "draft")
    bundle.compose_text([], [])

    assert_no_match(/PING response/, bundle.bundle_text)
  end
end
