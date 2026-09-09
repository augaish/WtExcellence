require "test_helper"

class Dashboard::CompanyModulesGatingTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!

    @company = Company.create!(
      name: "Gating Co #{SecureRandom.hex(4)}",
      license_seats: 10,
      credits: 100,
      is_active: true
    )

    @admin = User.create!(
      email: "gate-admin-#{SecureRandom.hex(4)}@example.com",
      password: "password123", password_confirmation: "password123",
      name: "Company Admin", is_active: true
    )
    CompanyUser.create!(company: @company, user: @admin, role: CompanyUser::ROLES[:company_admin])

    @super = User.create!(
      email: "gate-super-#{SecureRandom.hex(4)}@example.com",
      password: "password123", password_confirmation: "password123",
      name: "Super Admin", is_active: true, role: "super_admin"
    )
  end

  test "a disabled module redirects the company user to the overview" do
    @company.set_module!(:capa, false)
    sign_in @admin

    get dashboard_capa_management_path

    assert_redirected_to dashboard_overview_path
  end

  test "an enabled module is not blocked by the gate" do
    @company.set_module!(:capa, true)
    sign_in @admin

    get dashboard_capa_management_path

    # The gate must NOT bounce the user to the overview when the module is on.
    landed = response.redirect? ? URI(response.location.to_s).path : request.path
    assert_not_equal dashboard_overview_path, landed
  end

  test "a platform admin bypasses the module gate even when disabled" do
    @company.set_module!(:capa, false)
    sign_in @super

    get dashboard_capa_management_path

    # Super admin is never gated by module entitlements.
    landed = response.redirect? ? URI(response.location.to_s).path : request.path
    assert_not_equal dashboard_overview_path, landed
  end

  test "super admin can toggle a company's module" do
    sign_in @super
    assert @company.module_enabled?(:risk)

    patch dashboard_toggle_company_module_path(@company, "risk")

    assert_response :success
    body = JSON.parse(response.body)
    assert body["success"]
    assert_equal false, body["enabled"]
    refute @company.reload.module_enabled?(:risk)
  end

  test "a company admin cannot toggle modules" do
    sign_in @admin

    patch dashboard_toggle_company_module_path(@company, "risk")

    assert_response :forbidden
    assert @company.reload.module_enabled?(:risk)
  end

  test "toggling an unknown module key is rejected" do
    sign_in @super

    patch dashboard_toggle_company_module_path(@company, "bogus")

    assert_response :unprocessable_entity
  end

  test "company detail page renders the Modules section for a super admin" do
    sign_in @super

    get dashboard_account_management_company_path(@company)

    assert_response :success
    assert_select "h2", text: I18n.t("modules.title")
    # A toggle link exists for each module in the registry.
    assert_select "a[data-action='click->account-management#toggleModule']",
      count: Company::MODULES.size
  end

  test "Process Architecture, P&P and Authorities are separate switches" do
    assert Company::MODULES.key?(:processes)
    assert Company::MODULES.key?(:pp)
    assert Company::MODULES.key?(:authorities)
    assert_equal I18n.t("doa.title"), I18n.t(Company::MODULES[:authorities][:label_key])
  end
end
