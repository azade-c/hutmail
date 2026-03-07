require "test_helper"
require "ostruct"

class BundleFormatterTest < ActiveSupport::TestCase
  test "format_size formats bytes" do
    assert_equal "500 B", BundleFormatter.format_size(500)
    assert_equal "1.0 KB", BundleFormatter.format_size(1024)
    assert_equal "1.5 KB", BundleFormatter.format_size(1536)
    assert_equal "1.0 MB", BundleFormatter.format_size(1024 * 1024)
  end

  test "format_attachments lists files" do
    meta = [ { name: "photo.jpg", size: 245000, content_type: "image/jpeg" } ]
    result = BundleFormatter.format_attachments(meta)
    assert_equal "📎 photo.jpg (239.3 KB)", result
  end

  test "format_attachments returns nil for empty" do
    assert_nil BundleFormatter.format_attachments(nil)
    assert_nil BundleFormatter.format_attachments([])
  end

  test "format_screener truncates when over budget" do
    messages = 20.times.map do |i|
      OpenStruct.new(
        hutmail_id: "01mar.GM.#{i + 1}",
        from_name: "Sender #{i}",
        from_address: "sender#{i}@example.com",
        subject: "Subject #{i}",
        stripped_size: 1000
      )
    end

    # Very small budget
    result = BundleFormatter.format_screener(messages, 200)
    assert_includes result, "SCREENER"
    assert_includes result, "more messages pending"
  end

  test "format_screener includes all when budget allows" do
    messages = [
      OpenStruct.new(hutmail_id: "01mar.GM.1", from_name: "Bob", from_address: "bob@ex.com", subject: "Hello", stripped_size: 500)
    ]

    result = BundleFormatter.format_screener(messages, Float::INFINITY)
    assert_includes result, "01mar.GM.1"
    assert_includes result, "Bob"
    assert_not_includes result, "more messages pending"
  end
end
