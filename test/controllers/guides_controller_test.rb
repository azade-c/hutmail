require "test_helper"

class GuidesControllerTest < ActionDispatch::IntegrationTest
  test "show is reachable without authentication" do
    get guide_path

    assert_response :success
    assert_select "h1", /Comment marche Hutmail/
  end

  test "guide links to the lightweight commands reference" do
    get guide_path

    assert_response :success
    assert_select "a[href=?]", commands_path
  end
end
