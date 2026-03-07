require "test_helper"

class BoatCommandParserTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "parses STATUS command" do
    text = "===CMD===\nSTATUS\n===END==="
    parser = BoatCommandParser.new(@user)
    parser.parse_and_execute(text)

    assert_equal 1, parser.results.size
    assert_equal "STATUS", parser.results.first[:command]
    assert_equal :ok, parser.results.first[:status]
    assert_includes parser.results.first[:message], "pending"
  end

  test "parses DROP with hutmail ids" do
    text = "===CMD===\nDROP 01mar.GM.1\n===END==="
    parser = BoatCommandParser.new(@user)
    parser.parse_and_execute(text)

    result = parser.results.first
    assert_equal "DROP 01mar.GM.1", result[:command]
  end

  test "parses MSG blocks" do
    text = "===MSG bob@example.com===\nHello from the sea!\n===END==="
    parser = BoatCommandParser.new(@user)
    parser.parse_and_execute(text)

    result = parser.results.first
    assert_equal "MSG bob@example.com", result[:command]
    assert_equal :ok, result[:status]
  end

  test "ignores comments in commands" do
    text = "===CMD===\n# This is a comment\nSTATUS\n===END==="
    parser = BoatCommandParser.new(@user)
    parser.parse_and_execute(text)

    assert_equal 1, parser.results.size
    assert_equal "STATUS", parser.results.first[:command]
  end

  test "handles multiple commands" do
    text = "===CMD===\nSTATUS\nPAUSE 3d\n===END==="
    parser = BoatCommandParser.new(@user)
    parser.parse_and_execute(text)

    assert_equal 2, parser.results.size
  end

  test "handles unknown commands" do
    text = "===CMD===\nFOOBAR\n===END==="
    parser = BoatCommandParser.new(@user)
    parser.parse_and_execute(text)

    assert_equal :unknown, parser.results.first[:status]
  end
end
