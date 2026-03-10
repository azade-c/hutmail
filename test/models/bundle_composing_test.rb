require "test_helper"
require "ostruct"

class BundleComposingTest < ActiveSupport::TestCase
  test "format_size formats bytes" do
    assert_equal "500 B", Bundle.format_size(500)
    assert_equal "1.0 KB", Bundle.format_size(1024)
    assert_equal "1.5 KB", Bundle.format_size(1536)
    assert_equal "1.0 MB", Bundle.format_size(1024 * 1024)
  end
end
