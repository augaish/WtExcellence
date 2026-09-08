require "test_helper"

class Dashboard::OrgChartTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!

    @company = Company.create!(name: "Chart Co #{SecureRandom.hex(4)}", license_seats: 10, credits: 50, is_active: true)
    @admin = User.create!(email: "chart-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: "Chart Admin", is_active: true)
    CompanyUser.create!(company: @company, user: @admin, role: CompanyUser::ROLES[:company_admin])

    @group = @company.org_groups.create!(name_en: "Support", color: "#0B4F6C")
    @minister = @company.org_units.create!(name_en: "Minister", name_ar: "الوزير", level: 1)
    @finance = @company.org_units.create!(name_en: "Finance", level: 2, parent: @minister,
      org_group: @group, mandates: [ "Prepare the annual budget", "Monitor spending" ])
  end

  test "the chart draws the structure with its groups and mandates" do
    sign_in @admin
    get dashboard_org_units_chart_path

    assert_response :success
    assert_select "svg"
    assert_includes response.body, %(data-org-chart-unit-id-param="#{@finance.id}")
    assert_includes response.body, "#0B4F6C"
    assert_includes response.body, "Prepare the annual budget"
    assert_select "[data-controller=?]", "org-chart"
  end

  test "a unit with no mandates says so rather than showing an empty list" do
    sign_in @admin
    get dashboard_org_units_chart_path

    assert_includes response.body, I18n.t("org_structure.chart.no_mandates")
  end

  test "inactive units are hidden unless asked for" do
    hidden = @company.org_units.create!(name_en: "Retired Unit", level: 2, parent: @minister, active: false)

    sign_in @admin
    get dashboard_org_units_chart_path
    assert_not_includes response.body, "Retired Unit"

    get dashboard_org_units_chart_path(show_inactive: "1")
    assert_includes response.body, "Retired Unit"
  end

  test "the chart renders in Arabic" do
    sign_in @admin
    get dashboard_org_units_chart_path(locale: "ar")

    assert_response :success
    assert_includes response.body, "الوزير"
  end

  test "an empty structure explains what to do instead of drawing nothing" do
    # Deactivated rather than destroyed: units with children are protected from
    # deletion, and the empty chart is what matters here.
    @company.org_units.update_all(active: false)

    sign_in @admin
    get dashboard_org_units_chart_path

    assert_includes response.body, I18n.t("org_structure.chart.empty")
  end

  test "the list and the chart link to each other" do
    sign_in @admin

    get dashboard_org_units_path
    assert_select "a[href=?]", dashboard_org_units_chart_path

    get dashboard_org_units_chart_path
    assert_select "a[href=?]", dashboard_org_units_path
  end

  test "another company's structure is not drawn" do
    other = Company.create!(name: "Other #{SecureRandom.hex(4)}", license_seats: 5, credits: 1, is_active: true)
    other.org_units.create!(name_en: "Foreign Unit", level: 1)

    sign_in @admin
    get dashboard_org_units_chart_path

    assert_not_includes response.body, "Foreign Unit"
  end
end
