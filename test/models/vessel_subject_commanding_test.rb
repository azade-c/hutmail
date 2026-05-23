require "test_helper"

class VesselSubjectCommandingTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  setup do
    @vessel = vessels(:one)
  end

  test "parses STATUS from subject and queues immediate response" do
    assert_difference "@vessel.command_responses.count", 1 do
      assert_enqueued_with(job: CommandResponse::DeliverJob) do
        results = @vessel.parse_and_execute_subject("STATUS")
        assert_equal 1, results.size
        assert_equal "STATUS", results.first[:command]
      end
    end

    cr = @vessel.command_responses.last
    assert_equal "subject", cr.source
    assert_equal "STATUS", cr.command
    assert_equal "pending", cr.status
    assert_match(/STATUS hutmail/, cr.response_text)
  end

  test "PING from subject returns PONG with UTC timestamp" do
    @vessel.parse_and_execute_subject("PING")
    cr = @vessel.command_responses.last
    assert_equal "PING", cr.command
    assert_match(/\APONG \d{4}-\d{2}-\d{2}T\d{2}:\d{2}Z hutmail\z/, cr.response_text)
  end

  test "HELP from subject lists commands" do
    @vessel.parse_and_execute_subject("HELP")
    cr = @vessel.command_responses.last
    assert_equal "HELP", cr.command
    assert_match(/HUTMAIL commands/, cr.response_text)
  end

  test "strips Re: and Fwd: prefixes" do
    assert_difference "@vessel.command_responses.count", 1 do
      @vessel.parse_and_execute_subject("Re: Fwd: STATUS")
    end
    assert_equal "STATUS", @vessel.command_responses.last.command
  end

  test "ignores unknown subject (no command verb)" do
    assert_no_difference "@vessel.command_responses.count" do
      results = @vessel.parse_and_execute_subject("Re: bundle 23may 09:15")
      assert_empty results
    end
  end

  test "rejects non-allowed verbs from subject" do
    assert_no_difference "@vessel.command_responses.count" do
      results = @vessel.parse_and_execute_subject("PAUSE 2h")
      assert_empty results
    end
  end

  test "body STATUS queues deferred response (not delivered immediately)" do
    assert_no_enqueued_jobs only: CommandResponse::DeliverJob do
      assert_difference "@vessel.command_responses.count", 1 do
        @vessel.parse_and_execute_commands("===CMD===\nSTATUS\n===END===")
      end
    end
    cr = @vessel.command_responses.last
    assert_equal "body", cr.source
    assert_equal "pending", cr.status
  end

  test "unknown body command queues an error response" do
    assert_difference "@vessel.command_responses.count", 1 do
      @vessel.parse_and_execute_commands("===CMD===\nFOO\n===END===")
    end
    cr = @vessel.command_responses.last
    assert_equal "body", cr.source
    assert_match(/unknown command/i, cr.response_text)
  end
end
