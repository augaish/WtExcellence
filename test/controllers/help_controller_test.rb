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

  test "first login redirects to the user manual with the welcome banner" do
    sign_out :user
    assert_nil @user.user_manual_seen_at

    post user_session_path, params: { user: { email: @user.email, password: "password123" } }
    assert_redirected_to help_path(welcome: 1)
  end

  test "after dismissing, login goes straight to the dashboard" do
    sign_out :user
    @user.mark_user_manual_seen!

    post user_session_path, params: { user: { email: @user.email, password: "password123" } }
    assert_redirected_to dashboard_overview_path
  end

  test "dismiss marks the manual as seen and returns to the dashboard" do
    post dismiss_help_path
    assert_redirected_to dashboard_overview_path
    assert @user.reload.user_manual_seen?
  end

  test "welcome banner is not shown once the manual has been seen" do
    @user.mark_user_manual_seen!

    get help_path(welcome: 1)
    assert_response :success
    assert_no_match(/#{Regexp.escape(I18n.t('help.welcome_title'))}/, @response.body)
  end

  test "welcome banner shows on first-run welcome visit" do
    get help_path(welcome: 1)
    assert_response :success
    assert_match(/#{Regexp.escape(I18n.t('help.welcome_title'))}/, @response.body)
  end
end
