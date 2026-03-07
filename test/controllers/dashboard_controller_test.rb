require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  include SessionTestHelper

  setup do
    @user = users(:one)
    sign_in_as @user
  end

  test "should get dashboard" do
    get root_url
    assert_response :success
  end
end
