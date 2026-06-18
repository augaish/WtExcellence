require "test_helper"

class Dashboard::RiskManagementControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = Company.create!(
      name: "Risk Co #{SecureRandom.hex(4)}",
      license_seats: 5,
      is_active: true
    )

    @admin_user = User.create!(
      email: "risk.admin.#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "Risk Admin",
      is_active: true
    )
    CompanyUser.create!(company: @company, user: @admin_user, role: CompanyUser::ROLES[:company_admin])

    @risk_manager_user = User.create!(
      email: "risk.manager.#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "Risk Manager",
      is_active: true
    )
    CompanyUser.create!(company: @company, user: @risk_manager_user, role: CompanyUser::ROLES[:company_risk_manager])

    @viewer_user = User.create!(
      email: "risk.viewer.#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "Risk Viewer",
      is_active: true
    )
    CompanyUser.create!(company: @company, user: @viewer_user, role: CompanyUser::ROLES[:company_viewer])
  end

  test "company admin can view the risk register" do
    sign_in @admin_user, scope: :user

    get dashboard_risk_management_index_path

    assert_response :success
  end

  test "risk manager can view and create risks" do
    sign_in @risk_manager_user, scope: :user

    get dashboard_risk_management_index_path
    assert_response :success

    assert_difference "Risk.count", 1 do
      post dashboard_risk_management_index_path, params: {
        risk: { title: "Vendor outage", likelihood: 3, impact: 4 }
      }
    end
  end

  test "viewer without risk privileges is redirected" do
    sign_in @viewer_user, scope: :user

    get dashboard_risk_management_index_path

    assert_response :forbidden
  end
end
