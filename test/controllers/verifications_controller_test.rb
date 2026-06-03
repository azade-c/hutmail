require "test_helper"

class VerificationsControllerTest < ActionDispatch::IntegrationTest
  test "show is reachable without authentication" do
    get verification_path

    assert_response :success
    assert_select "h1", /Vérification end-to-end/
  end

  test "summarises the latest run date and overall pass status" do
    get verification_path

    assert_response :success
    assert_includes response.body, "3 juin 2026"
    assert_includes response.body, "PASS"
  end

  test "links back to the guide and commands pages" do
    get verification_path

    assert_response :success
    assert_select "a[href=?]", guide_path
    assert_select "a[href=?]", commands_path
  end
end
