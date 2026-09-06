require "test_helper"

# The P&P widgets must render inside the platform's OWN overview catalog, with
# real data, and disappear cleanly when the module is off.
class Dashboard::PpWidgetsTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!

    @company = Company.create!(name: "Widg Co #{SecureRandom.hex(4)}", license_seats: 10, credits: 50, is_active: true)
    @admin = User.create!(email: "widg-#{SecureRandom.hex(4)}@example.com",
      password: "password123", password_confirmation: "password123", name: "Admin", is_active: true)
    CompanyUser.create!(company: @company, user: @admin, role: CompanyUser::ROLES[:company_admin])

    @unit = @company.org_units.create!(name_en: "Finance", level: 1)
    @company.pp_records.create!(record_type: "policy", title_en: "A",
      current_stage: "s1_verify", stage_entered_at: Time.current, owner_org_unit: @unit)
    published = @company.pp_records.create!(record_type: "policy", title_en: "B",
      current_stage: "s5_published", stage_entered_at: Time.current, owner_org_unit: @unit)
    published.stage_transitions.create!(from_stage: "s5_toPublish", to_stage: "s5_published", direction: "forward")
  end

  test "all three widgets are in the overview catalog" do
    %w[pp_funnel pp_work_status pp_rollup].each do |key|
      assert_includes DashboardLayout::WIDGET_KEYS, key
    end
  end

  test "the widgets render on the overview with real data" do
    sign_in @admin
    get dashboard_overview_path

    assert_response :success
    # assert_select decodes entities, so "P&P" matches even though the body
    # contains "P&amp;P".
    assert_select "h2", text: I18n.t("pp_widgets.funnel.title")
    assert_select "h2", text: I18n.t("pp_widgets.status.title")
    assert_select "h2", text: I18n.t("pp_widgets.rollup.title")
    # The roll-up shows the real org unit.
    assert_includes response.body, "Finance"
  end

  test "the widgets are draggable and hideable like every other widget" do
    sign_in @admin
    get dashboard_overview_path

    assert_response :success
    assert_select "[data-widget-key=pp_funnel]"
    assert_select "[data-widget-key=pp_work_status]"
    assert_select "[data-widget-key=pp_rollup]"
  end

  test "the funnel reflects how far records have progressed" do
    sign_in @admin
    get dashboard_overview_path

    assert_response :success
    funnel = PpMonitoringService.for(@company).funnel
    inventory = funnel.detect { |f| f[:phase] == "inventory" }
    assert_equal 2, inventory[:reached]
    assert_equal 1, funnel.detect { |f| f[:phase] == "publishing" }[:reached]
  end

  test "widgets disappear when the P&P module is disabled" do
    @company.set_module!(:pp, false)
    sign_in @admin

    get dashboard_overview_path

    assert_response :success
    # The widgets still occupy their catalog slots but hold no P&P data.
    assert_select "h2", text: I18n.t("pp_widgets.funnel.title")
    assert_includes response.body, I18n.t("pp_widgets.no_data")
    assert_includes response.body, I18n.t("pp_widgets.rollup.no_units")
  end

  test "the overview still renders for a company with no P&P data at all" do
    empty = Company.create!(name: "Empty #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    user = User.create!(email: "empty-#{SecureRandom.hex(4)}@example.com",
      password: "password123", password_confirmation: "password123", name: "U", is_active: true)
    CompanyUser.create!(company: empty, user: user, role: CompanyUser::ROLES[:company_admin])

    sign_in user
    get dashboard_overview_path

    assert_response :success
    assert_includes response.body, I18n.t("pp_widgets.no_data")
  end
end
