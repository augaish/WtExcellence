require "test_helper"

# Phase 0: the sidebar is grouped Main Menu / Quality / P&P / Governance /
# Settings, and each group respects the per-company module entitlements.
class Dashboard::SidebarNavigationTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!

    @company = Company.create!(name: "Nav #{SecureRandom.hex(4)}", license_seats: 10, credits: 50, is_active: true)
    @admin = User.create!(email: "nav-#{SecureRandom.hex(4)}@example.com",
      password: "password123", password_confirmation: "password123", name: "Admin", is_active: true)
    CompanyUser.create!(company: @company, user: @admin, role: CompanyUser::ROLES[:company_admin])
  end

  test "org structure sits in the main menu and P&P has its own group" do
    sign_in @admin
    get dashboard_org_units_path

    assert_response :success
    assert_select "aside#sidebar" do
      assert_select "a[href=?]", dashboard_org_units_path
      assert_select "a[href=?]", dashboard_pp_processes_path
      assert_select "p", text: I18n.t("quality")
      assert_select "p", text: I18n.t("pp.title")
    end
  end

  test "disabling the org_structure module hides its link" do
    @company.set_module!(:org_structure, false)
    sign_in @admin

    get dashboard_overview_path
    assert_response :success
    assert_select "a[href=?]", dashboard_org_units_path, count: 0
  end

  test "disabling the pp module hides the whole P&P group" do
    @company.set_module!(:pp, false)
    sign_in @admin

    get dashboard_overview_path
    assert_response :success
    assert_select "a[href=?]", dashboard_pp_processes_path, count: 0
    assert_select "aside#sidebar p", text: I18n.t("pp.title"), count: 0
  end

  test "a disabled module also blocks the URL server-side" do
    @company.set_module!(:pp, false)
    sign_in @admin

    get dashboard_pp_processes_path
    assert_redirected_to dashboard_overview_path
  end

  test "org structure URL is blocked when its module is off" do
    @company.set_module!(:org_structure, false)
    sign_in @admin

    get dashboard_org_units_path
    assert_redirected_to dashboard_overview_path
  end
end
