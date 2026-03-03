require "test_helper"

class CommandParserTest < ActiveSupport::TestCase
  test "parses DROP LAST" do
    result = CommandParser.parse("===CMD===\nDROP LAST\n===END===")

    assert result.valid?
    assert_equal 1, result.commands.size
    assert_equal "DROP", result.commands.first.action
    assert_equal "last", result.commands.first.args[:target]
  end

  test "parses DROP with message numbers" do
    result = CommandParser.parse("===CMD===\nDROP 3 5\n===END===")

    assert result.valid?
    cmd = result.commands.first
    assert_equal "DROP", cmd.action
    assert_equal "messages", cmd.args[:target]
    assert_equal [ 3, 5 ], cmd.args[:indices]
  end

  test "parses SEND with quoted message" do
    result = CommandParser.parse('===CMD===
SEND bob@example.com "On arrive mardi"
===END===')

    assert result.valid?
    cmd = result.commands.first
    assert_equal "SEND", cmd.action
    assert_equal "bob@example.com", cmd.args[:to]
    assert_equal "On arrive mardi", cmd.args[:message]
  end

  test "parses URGENT" do
    result = CommandParser.parse('===CMD===
URGENT famille@castors.fr "Tout va bien"
===END===')

    assert result.valid?
    cmd = result.commands.first
    assert_equal "URGENT", cmd.action
    assert_equal "famille@castors.fr", cmd.args[:to]
  end

  test "parses PAUSE with duration" do
    result = CommandParser.parse("===CMD===\nPAUSE 3d\n===END===")

    assert result.valid?
    assert_equal "PAUSE", result.commands.first.action
    assert_equal "3d", result.commands.first.args[:duration]
  end

  test "parses RESUME" do
    result = CommandParser.parse("===CMD===\nRESUME\n===END===")

    assert result.valid?
    assert_equal "RESUME", result.commands.first.action
  end

  test "parses STATUS" do
    result = CommandParser.parse("===CMD===\nSTATUS\n===END===")

    assert result.valid?
    assert_equal "STATUS", result.commands.first.action
  end

  test "parses WHITELIST add" do
    result = CommandParser.parse("===CMD===\nWHITELIST add bob@example.com\n===END===")

    assert result.valid?
    cmd = result.commands.first
    assert_equal "WHITELIST", cmd.action
    assert_equal "add", cmd.args[:sub_action]
    assert_equal "bob@example.com", cmd.args[:email]
  end

  test "parses BLACKLIST add" do
    result = CommandParser.parse("===CMD===\nBLACKLIST add spam@junk.com\n===END===")

    assert result.valid?
    cmd = result.commands.first
    assert_equal "BLACKLIST", cmd.action
    assert_equal "add", cmd.args[:sub_action]
  end

  test "parses multiple commands" do
    result = CommandParser.parse("===CMD===\nDROP 3\nSTATUS\nWHITELIST add friend@test.com\n===END===")

    assert result.valid?
    assert_equal 3, result.commands.size
  end

  test "ignores comments" do
    result = CommandParser.parse("===CMD===\n# this is a comment\nSTATUS\n===END===")

    assert result.valid?
    assert_equal 1, result.commands.size
  end

  test "returns error for missing block" do
    result = CommandParser.parse("just some text")

    refute result.valid?
    assert result.errors.any? { |e| e.include?("No ===CMD===") }
  end

  test "returns error for unknown command" do
    result = CommandParser.parse("===CMD===\nFLY\n===END===")

    refute result.valid?
    assert result.errors.any? { |e| e.include?("unknown command") }
  end

  test "returns error for GET (removed)" do
    result = CommandParser.parse("===CMD===\nGET 1 2\n===END===")

    refute result.valid?
    assert result.errors.any? { |e| e.include?("unknown command") }
  end

  test "is case insensitive" do
    result = CommandParser.parse("===CMD===\ndrop last\n===END===")

    assert result.valid?
    assert_equal "DROP", result.commands.first.action
  end

  test "execute DROP LAST sets flag" do
    result = CommandParser.parse("===CMD===\nDROP LAST\n===END===")
    execution = CommandParser.execute(result.commands, message_count: 5)

    assert execution[:drop_last]
    assert execution[:actions_log].any? { |l| l.include?("DROP LAST") }
  end

  test "execute DROP messages validates indices" do
    result = CommandParser.parse("===CMD===\nDROP 2 99\n===END===")
    execution = CommandParser.execute(result.commands, message_count: 5)

    assert_equal [ 2 ], execution[:drop_indices]
    assert execution[:actions_log].any? { |l| l.include?("Invalid") }
  end

  test "execute generates log for all command types" do
    result = CommandParser.parse("===CMD===\nDROP 1\nSTATUS\nPAUSE 2d\n===END===")
    execution = CommandParser.execute(result.commands, message_count: 5)

    assert_equal 3, execution[:actions_log].size
  end
end
