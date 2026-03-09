require "test_helper"

class VesselCommandingTest < ActiveSupport::TestCase
  setup do
    @vessel = vessels(:one)
  end

  test "parses STATUS command" do
    text = "===CMD===\nSTATUS\n===END==="
    results = @vessel.parse_and_execute_commands(text)

    assert_equal 1, results.size
    assert_equal "STATUS", results.first[:command]
    assert_equal :ok, results.first[:status]
    assert_includes results.first[:message], "pending"
  end

  test "parses DROP with hutmail ids" do
    text = "===CMD===\nDROP 01mar.GM.1\n===END==="
    results = @vessel.parse_and_execute_commands(text)

    result = results.first
    assert_equal "DROP 01mar.GM.1", result[:command]
  end

  test "parses MSG blocks" do
    text = "===MSG bob@example.com===\nHello from the sea!\n===END==="
    results = @vessel.parse_and_execute_commands(text)

    result = results.first
    assert_equal "MSG bob@example.com", result[:command]
    assert_equal :ok, result[:status]
  end

  test "ignores comments in commands" do
    text = "===CMD===\n# This is a comment\nSTATUS\n===END==="
    results = @vessel.parse_and_execute_commands(text)

    assert_equal 1, results.size
    assert_equal "STATUS", results.first[:command]
  end

  test "handles multiple commands" do
    text = "===CMD===\nSTATUS\nPAUSE 3d\n===END==="
    results = @vessel.parse_and_execute_commands(text)

    assert_equal 2, results.size
  end

  test "handles unknown commands" do
    text = "===CMD===\nFOOBAR\n===END==="
    results = @vessel.parse_and_execute_commands(text)

    assert_equal :unknown, results.first[:status]
  end
end
