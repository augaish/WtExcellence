require "test_helper"

class Dashboard::OrgUnitsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!

    @company = Company.create!(name: "OrgCtl #{SecureRandom.hex(4)}", license_seats: 10, credits: 50, is_active: true)

    @admin = User.create!(email: "org-admin-#{SecureRandom.hex(4)}@example.com",
      password: "password123", password_confirmation: "password123", name: "Admin", is_active: true)
    CompanyUser.create!(company: @company, user: @admin, role: CompanyUser::ROLES[:company_admin])

    @viewer = User.create!(email: "org-viewer-#{SecureRandom.hex(4)}@example.com",
      password: "password123", password_confirmation: "password123", name: "Viewer", is_active: true)
    CompanyUser.create!(company: @company, user: @viewer, role: CompanyUser::ROLES[:company_viewer])

    @ceo = @company.org_units.create!(name_en: "CEO", level: 1, code: "01")
  end

  test "index renders the tree for a company user" do
    sign_in @admin
    get dashboard_org_units_path

    assert_response :success
    assert_select "body", text: /CEO/
  end

  test "a viewer can see the tree but gets no manage actions" do
    sign_in @viewer
    get dashboard_org_units_path

    assert_response :success
    assert_select "a[href=?]", new_dashboard_org_unit_path, count: 0
  end

  test "a viewer cannot create a unit" do
    sign_in @viewer
    assert_no_difference -> { @company.org_units.count } do
      post dashboard_org_units_path, params: { org_unit: { name_en: "Sneaky", level: 2 } }
    end
    assert_redirected_to dashboard_org_units_path
  end

  test "admin creates a unit with mandates" do
    sign_in @admin

    assert_difference -> { @company.org_units.count }, 1 do
      post dashboard_org_units_path, params: {
        org_unit: { name_en: "Quality", name_ar: "الجودة", level: 2, parent_id: @ceo.id,
                    mandates: [ "Own the QMS", "" ] }
      }
    end

    unit = @company.org_units.order(:created_at).last
    assert_equal "Quality", unit.name_en
    assert_equal [ "Own the QMS" ], unit.mandate_list
    assert_equal @ceo.id, unit.parent_id
  end

  test "rejects a unit reporting to a lower-ranked parent" do
    sign_in @admin
    manager = @company.org_units.create!(name_en: "Manager", level: 5, parent: @ceo)

    post dashboard_org_units_path, params: {
      org_unit: { name_en: "Director", level: 4, parent_id: manager.id }
    }

    assert_response :unprocessable_entity
    assert_nil @company.org_units.find_by(name_en: "Director")
  end

  test "new form suggests the next code" do
    sign_in @admin
    get new_dashboard_org_unit_path(parent_id: @ceo.id)

    assert_response :success
    assert_select "input[name='org_unit[code]'][value=?]", "01-01"
  end

  test "toggle_active flips the unit" do
    sign_in @admin
    patch toggle_active_dashboard_org_unit_path(@ceo)

    refute @ceo.reload.active?
  end

  test "a unit with children cannot be deleted" do
    sign_in @admin
    @company.org_units.create!(name_en: "Child", level: 2, parent: @ceo)

    assert_no_difference -> { @company.org_units.count } do
      delete dashboard_org_unit_path(@ceo)
    end
    assert_redirected_to dashboard_org_units_path
  end

  test "settings page lists all six levels" do
    sign_in @admin
    get settings_dashboard_org_units_path

    assert_response :success
    assert_select "input[name='levels[1][name_en]']"
    assert_select "input[name='levels[6][name_en]']"
  end

  test "saving level names creates definitions" do
    sign_in @admin

    patch settings_dashboard_org_units_path, params: {
      levels: { "1" => { name_en: "CEO", name_ar: "الرئيس التنفيذي" }, "2" => { name_en: "VP", name_ar: "" } }
    }

    assert_equal "CEO", @company.org_level_definitions.find_by(level: 1).name_en
    assert_equal "VP", @company.org_level_definitions.find_by(level: 2).name_en
  end

  test "the CSV template downloads with the documented headers" do
    sign_in @admin
    get template_dashboard_org_units_path

    assert_response :success
    assert_includes response.body, "code,name_en,name_ar,level,parent_code"
  end
end
