require "test_helper"

class HelpControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = Company.create!(name: "Help Co #{SecureRandom.hex(4)}", license_seats: 5, is_active: true)
    @user = User.create!(
      email: "help.#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "Help User",
      is_active: true
    )
    CompanyUser.create!(company: @company, user: @user, role: CompanyUser::ROLES[:company_viewer])
    sign_in @user, scope: :user
  end

  test "index renders" do
    get help_path
    assert_response :success
    assert_match I18n.t("help.title"), @response.body
  end

  test "every topic renders in both locales without error" do
    HelpController::TOPICS.each do |slug|
      get help_topic_path(slug)
      assert_response :success, "topic #{slug} failed to render"
      assert_no_match(/translation missing/, @response.body, "missing translation in #{slug}")

      get help_topic_path(slug, locale: "ar")
      assert_response :success, "topic #{slug} (ar) failed to render"
      assert_no_match(/translation missing/, @response.body, "missing translation in #{slug} (ar)")
    end
  end

  test "unknown topic redirects to index" do
    get help_topic_path("does_not_exist")
    assert_redirected_to help_path
  end
end
