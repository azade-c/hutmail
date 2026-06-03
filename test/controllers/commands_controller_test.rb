require "test_helper"

class CommandsControllerTest < ActionDispatch::IntegrationTest
  test "show is reachable without authentication" do
    get commands_path

    assert_response :success
    assert_select "h1", /Commandes Hutmail/
  end

  test "uses the lightweight plain layout without external assets" do
    get commands_path

    assert_response :success
    assert_select "nav.nav", false
    assert_select "link[rel=stylesheet]", false
    assert_select "script", false
  end

  test "documents the core executable commands" do
    get commands_path

    assert_response :success
    %w[STATUS PING HELP GET SEND URGENT REPLY MSG].each do |command|
      assert_includes response.body, command
    end
  end
end
