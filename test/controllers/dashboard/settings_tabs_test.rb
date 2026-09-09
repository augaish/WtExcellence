require "test_helper"

# Documenter settings live under General Settings as a tab.
class Dashboard::SettingsTabsTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!
    @company = Company.create!(name: "Tabs #{SecureRandom.hex(4)}", license_seats: 10, credits: 50, is_active: true)
    @company.update!(enabled_modules: Company::MODULES) if @company.respond_to?(:enabled_modules)

    @admin = User.create!(email: "tabs-admin-#{SecureRandom.hex(4)}@example.com",
      password: "password123", password_confirmation: "password123", name: "Admin", is_active: true)
    CompanyUser.create!(company: @company, user: @admin, role: CompanyUser::ROLES[:company_admin])

    @viewer = User.create!(email: "tabs-viewer-#{SecureRandom.hex(4)}@example.com",
      password: "password123", password_confirmation: "password123", name: "Viewer", is_active: true)
    CompanyUser.create!(company: @company, user: @viewer, role: CompanyUser::ROLES[:company_viewer])
  end

  test "an admin sees the Documenter tab on General Settings and can open it" do
    sign_in @admin
    get dashboard_general_settings_path
    assert_response :success
    assert_select "a[href=?]", dashboard_general_settings_documenter_path

    get dashboard_general_settings_documenter_path
    assert_response :success
    assert_select "a[aria-current=page]", text: I18n.t("settings_tabs.documenter")
  end

  test "a viewer gets no Documenter tab" do
    sign_in @viewer
    get dashboard_general_settings_path
    assert_response :success
    assert_select "a[href=?]", dashboard_general_settings_documenter_path, count: 0
  end

  test "the Documenter worklist no longer carries a settings button" do
    sign_in @admin
    get dashboard_documenter_path
    assert_response :success
    assert_select "a[href=?]", dashboard_documenter_settings_path, count: 0
  end
end
