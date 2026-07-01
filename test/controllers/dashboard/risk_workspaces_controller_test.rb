require "test_helper"

class Dashboard::RiskWorkspacesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = Company.create!(
      name: "Risk Workspace Co #{SecureRandom.hex(4)}",
      license_seats: 5,
      is_active: true
    )

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

  test "risk manager can create and view a workspace" do
    sign_in @risk_manager_user, scope: :user

    assert_difference "RiskWorkspace.count", 1 do
      post dashboard_risk_workspaces_path, params: { risk_workspace: { name: "ISO 27001" } }
    end

    workspace = RiskWorkspace.last
    get dashboard_risk_workspace_path(workspace)
    assert_response :success
  end

  test "viewer without risk privileges is redirected" do
    sign_in @viewer_user, scope: :user

    get dashboard_risk_workspaces_path

    assert_response :forbidden
  end

  test "risk manager is blocked from CAPA management, Standards, and Library" do
    sign_in @risk_manager_user, scope: :user

    get dashboard_capa_management_path
    assert_response :forbidden

    get standards_path
    assert_response :forbidden

    get library_path
    assert_response :forbidden
  end
end
