require "test_helper"

# The sidebar rail: every permitted item, counts of waiting work, Arabic side.
class SidebarRailTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!
    @company = Company.create!(name: "Rail Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @qm = User.create!(email: "rail-#{SecureRandom.hex(4)}@example.com", password: "Password1234",
      password_confirmation: "Password1234", name: "Rail Tester", is_active: true)
    CompanyUser.create!(company: @company, user: @qm, role: CompanyUser::ROLES[:company_quality_manager])
    @qm.company_user.update!(pp_manager: true)
  end

  test "the rail lists the permitted items with icons, labels, headings and the pin" do
    sign_in @qm
    get dashboard_overview_path
    assert_select "#sidebar[data-controller=sidebar-rail][data-expanded=false]"
    assert_select "#sidebar a[data-sidebar-rail-target=item][href=?]", dashboard_documenter_path
    assert_select "#sidebar a[data-sidebar-rail-target=item][href=?]", dashboard_account_management_path, 0
    assert_select "#sidebar .rail-heading", text: I18n.t("main_menu")
    assert_select "#sidebar [data-sidebar-rail-target=pin][aria-pressed=false]"
    assert_select "#sidebar input[type=search]"
    assert_select "#sidebar a[aria-current=page][href=?]", dashboard_overview_path
    assert_includes response.body, "RT", "the initials sit on the rail"
  end

  test "counts of waiting work sit on the items" do
    @company.pp_records.create!(record_type: "policy", title_en: "Verify me", description: "x", owner_user: @qm, verifier_user: @qm)
    capa = Capa.create!(company: @company, title: "Late", description: "d", source: "audit", status: :assigned, created_by: @qm)
    CapaAssignment.create!(capa: capa, company_user: @qm.company_user)
    action = capa.capa_actions.create!(title: "Fix", action_type: "corrective", status: "started")
    CapaActionAssignment.create!(capa_action: action, company_user: @qm.company_user)

    sign_in @qm
    get dashboard_overview_path
    assert_select "#sidebar a[href=?] .rail-badge", dashboard_documenter_path
    assert_select "#sidebar a[href=?] .rail-badge", dashboard_capa_management_path, text: "1"
    assert_select "#sidebar a[href=?] .rail-badge", dashboard_pp_records_path, 0
    assert_select "#sidebar a[href=?] .rail-badge", dashboard_capa_management_path, 1, "the count is shown once, on the icon"
    assert_select "#sidebar a[href=?] svg", dashboard_capa_management_path
  end

  test "in Arabic the rail reads right to left" do
    sign_in @qm
    get dashboard_overview_path(locale: :ar)
    assert_select "#sidebar[dir=rtl]"
    assert_select "#sidebar input[placeholder=?]", I18n.t("sidebar_rail.search", locale: :ar)
  end
end
