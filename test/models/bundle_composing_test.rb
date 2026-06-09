require "test_helper"
require "ostruct"

class BundleComposingTest < ActiveSupport::TestCase
  setup do
    @vessel = vessels(:one)
    @account = mail_accounts(:gmail)
  end

  test "format_size formats bytes" do
    assert_equal "500 B", Bundle.format_size(500)
    assert_equal "1.0 KB", Bundle.format_size(1024)
    assert_equal "1.5 KB", Bundle.format_size(1536)
    assert_equal "1.0 MB", Bundle.format_size(1024 * 1024)
  end

  test "compose! closes every dispatch with the remaining 7-day credit" do
    @vessel.update!(daily_budget_kb: 100, budget_topup_bytes: 0)
    message = long_body_message

    bundle = @vessel.bundles.create!(status: "draft")
    bundle.compose!([ message ], [])

    footer = bundle.bundle_text.lines.map(&:chomp).reject(&:blank?)[-2]
    assert_match(/\ARestent .+ \/ .+ \(7j glissants\)\z/, footer)
    # The footer reflects the balance net of this dispatch's own weight.
    expected_remaining = [ @vessel.budget_remaining - bundle.dispatch_size, 0 ].max
    assert_includes bundle.bundle_text, Bundle.format_size(expected_remaining)
    assert_includes bundle.bundle_text, Bundle.format_size(@vessel.budget_total)
  end

  test "dispatch_size accounts for the budget footer itself" do
    @vessel.update!(daily_budget_kb: 100)
    message = long_body_message

    bundle = @vessel.bundles.create!(status: "draft")
    bundle.compose!([ message ], [])

    assert_equal bundle.bundle_text.bytesize, bundle.dispatch_size
  end

  test "compose! truncates message bodies to the vessel char limit" do
    @vessel.update!(message_char_limit: 30)
    message = long_body_message

    bundle = @vessel.bundles.create!(status: "draft")
    bundle.compose!([ message ], [])

    assert_includes bundle.bundle_text, "// message tronqué, restent"
    assert_not_includes bundle.bundle_text, "x" * 100
  end

  test "compose! with truncate false keeps full bodies even when a limit is set" do
    @vessel.update!(message_char_limit: 30)
    message = long_body_message

    bundle = @vessel.bundles.create!(status: "draft")
    bundle.compose!([ message ], [], truncate: false)

    assert_includes bundle.bundle_text, "x" * 100
    assert_not_includes bundle.bundle_text, "message tronqué"
  end

  test "compose! never truncates when the vessel has no char limit" do
    @vessel.update!(message_char_limit: nil)
    message = long_body_message

    bundle = @vessel.bundles.create!(status: "draft")
    bundle.compose!([ message ], [])

    assert_includes bundle.bundle_text, "x" * 100
    assert_not_includes bundle.bundle_text, "message tronqué"
  end

  private
    def long_body_message
      body = "x" * 100
      @account.message_digests.create!(
        imap_uid: 300,
        imap_message_id: "compose-truncate@example.com",
        from_address: "bob@example.com",
        from_name: "Bob",
        subject: "Long body",
        date: Time.current,
        raw_size: 5000,
        stripped_body: body,
        stripped_size: body.length,
        status: :collected,
        collected_at: Time.current
      )
    end
end
