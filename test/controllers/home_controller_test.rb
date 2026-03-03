require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "should get index without authentication" do
    get root_url
    assert_response :success
    assert_match "HutMail", response.body
  end
end
