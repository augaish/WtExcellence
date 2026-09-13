require "test_helper"

# The account register never opens for a non-administrator, whatever URL they type.
class Dashboard::AccountRegisterAccessTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!
    @company = Company.create!(name: "Reg Co #{SecureRandom.hex(4)}", license_seats: 10, credits: 10, is_active: true)
    @other = Company.create!(name: "Other Co #{SecureRandom.hex(4)}", license_seats: 10, credits: 10, is_active: true)
    @outsider = create_user(@other, "outsider", CompanyUser::ROLES[:company_admin])
    @admin = create_user(@company, "reg-admin", CompanyUser::ROLES[:company_admin])
  end

  def create_user(company, prefix, role)
    user = User.create!(email: "#{prefix}-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: prefix.humanize, is_active: true)
    CompanyUser.create!(company: company, user: user, role: role)
    user
  end

  # Quality managers hold admin privileges in this product and keep the register.
  test "viewer, contributor, auditor and risk manager are turned away from every register page" do
    %i[company_viewer company_contributor company_auditor company_risk_manager].each do |role|
      sign_in create_user(@company, role.to_s, CompanyUser::ROLES[role])
      [ dashboard_account_management_path, dashboard_account_management_users_path, dashboard_account_management_company_path(@company) ].each do |path|
        get path
        assert_redirected_to dashboard_overview_path, "#{role} reached #{path}"
        assert_not_includes response.body, @outsider.email
      end
      get dashboard_account_management_users_path(q: @outsider.email)
      assert_redirected_to dashboard_overview_path
    end
  end

  test "a company admin sees only their own company's people" do
    sign_in @admin
    get dashboard_account_management_users_path
    assert_response :success
    assert_includes response.body, @admin.email
    assert_not_includes response.body, @outsider.email
  end
end
