require "test_helper"

# Six-user test F02: work assigned to someone without the governance licence
# opens as a scoped task page, never as a dead link.
class Dashboard::GovernanceTasksTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!
    @company = Company.create!(name: "Task Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @manager = create_user("rm", CompanyUser::ROLES[:company_risk_manager])
    @contributor = create_user("contrib", CompanyUser::ROLES[:company_contributor])
    @other = create_user("other", CompanyUser::ROLES[:company_contributor])
  end

  def create_user(prefix, role)
    user = User.create!(email: "#{prefix}-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: prefix.humanize, is_active: true)
    CompanyUser.create!(company: @company, user: user, role: role)
    user
  end

  test "a contributor assigned a commitment is told, sees it in their queue, opens the task and submits it" do
    sign_in @manager
    post dashboard_customer_commitments_path, params: { customer_commitment: {
      title: "Evidence delivery", customer_name: "Bank A", due_date: 3.days.from_now.to_date,
      owner_id: @contributor.company_user.id, acceptance_criteria: "Signed receipt" } }
    commitment = CustomerCommitment.find_by(title: "Evidence delivery")
    assert Notification.exists?(recipient: @contributor, kind: "governance_task_assigned", source: commitment)

    sign_in @contributor
    get dashboard_overview_path
    assert_select "a[href=?]", dashboard_commitment_task_path(commitment)
    assert_select "a[href=?]", dashboard_customer_commitment_path(commitment), 0

    get dashboard_customer_commitment_path(commitment)
    assert_response :see_other, "the register stays closed"

    get dashboard_commitment_task_path(commitment)
    assert_response :success
    assert_includes response.body, "Signed receipt"

    post dashboard_submit_commitment_task_path(commitment), params: { fulfillment_note: "" }
    assert_not commitment.reload.fulfilled?

    post dashboard_submit_commitment_task_path(commitment), params: { fulfillment_note: "Delivered and signed", delivered_on: Date.current }
    commitment.reload
    assert commitment.fulfilled?
    assert_equal [ "pending", @contributor ], [ commitment.acceptance_status, commitment.fulfilled_by ]
    assert Notification.exists?(recipient: @manager, kind: "governance_task_submitted", source: commitment)

    sign_in @other
    get dashboard_commitment_task_path(commitment)
    assert_redirected_to dashboard_overview_path
  end

  test "a contributor named control owner reports on the control from the task page" do
    sign_in @manager
    risk = Risk.create!(company: @company, title: "Supplier continuity", cause: "c", event: "e", impact_statement: "i",
      likelihood: 3, impact: 4, status: "identified", owner: @manager.company_user, created_by: @manager,
      control_owner: @contributor.company_user, treatment_plan: "Second supplier")
    patch dashboard_risk_management_path(risk), params: { risk: { control_owner_id: @contributor.company_user.id, treatment_plan: "Second supplier ready" } }

    sign_in @contributor
    get dashboard_overview_path
    assert_select "a[href=?]", dashboard_control_task_path(risk)
    get dashboard_risk_management_path(risk)
    assert_response :see_other

    get dashboard_control_task_path(risk)
    assert_response :success
    assert_includes response.body, "Second supplier"

    post dashboard_submit_control_task_path(risk), params: { control_evidence_note: "Contract signed with supplier B" }
    risk.reload
    assert_equal "Contract signed with supplier B", risk.control_evidence_note
    assert_not_nil risk.control_evidence_submitted_at
    assert Notification.exists?(recipient: @manager, kind: "governance_task_submitted", source: risk)

    get dashboard_overview_path
    assert_select "a[href=?]", dashboard_control_task_path(risk), 0, "submitted work leaves the queue"
  end
end
