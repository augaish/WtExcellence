require "test_helper"

# F12 — fixing one validation error removed a workspace the user could
# previously select, because the failure path re-rendered the form without
# loading its collections.
class Dashboard::RiskFormCollectionsTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!

    @company = Company.create!(name: "Form Co #{SecureRandom.hex(4)}", license_seats: 10, credits: 50, is_active: true)
    @admin = User.create!(email: "form-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: "Form Admin", is_active: true)
    CompanyUser.create!(company: @company, user: @admin, role: CompanyUser::ROLES[:company_admin])

    @workspace = @company.risk_workspaces.create!(name: "Workspace A")
    @risk = @company.risks.create!(title: "Supplier outage", likelihood: 3, impact: 3,
      risk_workspace: @workspace)
  end

  test "a failed update keeps every workspace the form offered" do
    sign_in @admin
    patch dashboard_risk_management_path(@risk), params: { risk: { title: "   " } }

    assert_response :unprocessable_entity
    assert_select "select[name=?] option[value=?]", "risk[risk_workspace_id]", @workspace.id
  end

  test "an admin can set and clear the company's risk appetite" do
    sign_in @admin
    patch dashboard_update_risk_appetite_path, params: { company: { risk_appetite_score: 8 } }

    assert_redirected_to dashboard_risk_management_index_path
    assert_equal 8, @company.reload.risk_appetite_score

    patch dashboard_update_risk_appetite_path, params: { company: { risk_appetite_score: "" } }
    assert_nil @company.reload.risk_appetite_score
  end

  test "a risk above appetite is flagged on its detail page" do
    @company.update!(risk_appetite_score: 5)

    sign_in @admin
    get dashboard_risk_management_path(@risk)

    assert_response :success
    assert_includes response.body, I18n.t("risk_methodology.above_appetite", appetite: 5)
  end

  test "a target is shown as an intention, not as current exposure" do
    @risk.update!(target_likelihood: 1, target_impact: 1)

    sign_in @admin
    get dashboard_risk_management_path(@risk)

    assert_includes response.body, I18n.t("risk_methodology.target_note")
    assert_includes response.body, I18n.t("risk_methodology.current_exposure")
  end

  test "a failed create keeps every workspace the form offered" do
    sign_in @admin
    post dashboard_risk_management_index_path, params: { risk: { title: "", likelihood: 3, impact: 3 } }

    assert_response :unprocessable_entity
    assert_select "select[name=?] option[value=?]", "risk[risk_workspace_id]", @workspace.id
  end
end
