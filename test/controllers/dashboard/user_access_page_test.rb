require "test_helper"

# Six-user test E02: an admin sees why a person can or cannot act.
class Dashboard::UserAccessPageTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!
    @company = Company.create!(name: "Access Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @admin = create_user("admin", CompanyUser::ROLES[:company_admin])
    @qm = create_user("qm", CompanyUser::ROLES[:company_quality_manager])
    @contributor = create_user("contrib", CompanyUser::ROLES[:company_contributor])
  end

  def create_user(prefix, role)
    user = User.create!(email: "#{prefix}-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: prefix.humanize, is_active: true)
    CompanyUser.create!(company: @company, user: user, role: role)
    user
  end

  test "the page explains a quality manager without the P&P designation and offers to designate them" do
    sign_in @admin
    get dashboard_account_management_users_path
    assert_select "a[href=?]", dashboard_user_access_path(@qm)

    get dashboard_user_access_path(@qm)
    assert_response :success
    assert_includes response.body, CGI.escapeHTML(I18n.t("access_page.reasons.quality_manager_not_designated"))
    assert_includes response.body, CGI.escapeHTML(I18n.t("access_page.setup.no_pp_manager"))
    assert_select "form[action=?]", dashboard_toggle_pp_manager_path(@qm)

    @qm.company_user.update!(pp_manager: true)
    get dashboard_user_access_path(@qm)
    assert_includes response.body, CGI.escapeHTML(I18n.t("access_page.reasons.pp_manager_designation"))
    assert_not_includes response.body, CGI.escapeHTML(I18n.t("access_page.setup.no_pp_manager"))
  end

  test "a contributor's governance access reads as assigned tasks only; a quality manager cannot open the page" do
    sign_in @admin
    get dashboard_user_access_path(@contributor)
    assert_includes response.body, CGI.escapeHTML(I18n.t("access_page.reasons.assigned_tasks_only"))
    assert_includes response.body, CGI.escapeHTML(I18n.t("access_page.levels.assigned"))

    sign_in @qm
    get dashboard_user_access_path(@contributor)
    assert_redirected_to dashboard_overview_path
  end
end

class CompanyAdminDesignatesManagersTest < ActionDispatch::IntegrationTest
  test "the company admin sees the P&P and Governance Manager toggles in the users list and can flip them" do
    Rails.application.reload_routes!
    company = Company.create!(name: "Desig Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    make = lambda do |prefix, role|
      u = User.create!(email: "#{prefix}-#{SecureRandom.hex(4)}@example.com", password: "password123",
        password_confirmation: "password123", name: prefix, is_active: true)
      CompanyUser.create!(company: company, user: u, role: role)
      u
    end
    admin = make.call("admin", CompanyUser::ROLES[:company_admin])
    qm = make.call("qm", CompanyUser::ROLES[:company_quality_manager])
    rm = make.call("rm", CompanyUser::ROLES[:company_risk_manager])

    sign_in admin
    get dashboard_account_management_users_path
    assert_select "form[action=?]", dashboard_toggle_pp_manager_path(qm)
    assert_select "form[action=?]", dashboard_toggle_gov_manager_path(rm)

    patch dashboard_toggle_pp_manager_path(qm)
    assert qm.company_user.reload.pp_manager
    patch dashboard_toggle_gov_manager_path(rm)
    assert rm.company_user.reload.gov_manager
  end
end
