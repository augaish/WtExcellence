require "test_helper"

# Risk/DoA round, group 3: the owner fills in the treatment, a risk manager
# accepts it or returns it with a reason.
class RiskTreatmentWorkflowTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!
    @company = Company.create!(name: "RT Co #{SecureRandom.hex(4)}", license_seats: 10, credits: 10, is_active: true)
    @admin = person("admin", :company_admin)
    @rm = person("rm", :company_risk_manager)
    @qm = person("qm", :company_quality_manager)
    @owner = person("owner", :company_viewer)
  end

  def person(prefix, role)
    user = User.create!(email: "#{prefix}-#{SecureRandom.hex(4)}@example.com", password: "Password1234",
      password_confirmation: "Password1234", name: prefix.humanize, is_active: true)
    CompanyUser.create!(company: @company, user: user, role: CompanyUser::ROLES[role])
    user
  end

  def create_risk(owner:)
    post "/dashboard/risk_management", params: { risk: { title: "Data centre flood", cause: "c", event: "e", impact_statement: "i",
      likelihood: 4, impact: 4, owner_id: owner.company_user.id } }
    Risk.find_by!(title: "Data centre flood")
  end

  test "owner fills the treatment, manager returns it with a reason, owner resubmits, admin accepts" do
    sign_in @rm
    risk = create_risk(owner: @owner)
    assert risk.awaiting_treatment?
    note = Notification.find_by!(recipient: @owner, kind: "risk_treatment_requested")
    assert_equal dashboard_treatment_task_path(risk), note.link_path

    sign_in @owner
    get dashboard_overview_path
    get dashboard_treatment_task_path(risk)
    assert_response :success
    assert_select "form[action=?]", dashboard_submit_treatment_task_path(risk)
    assert WorkQueue.new(user: @owner, company: @company).items.any? { |i| i.path == dashboard_treatment_task_path(risk) }

    post dashboard_submit_treatment_task_path(risk), params: { risk: { treatment_plan: "" } }
    assert risk.reload.awaiting_treatment?, "a plan is required"
    post dashboard_submit_treatment_task_path(risk), params: { risk: { treatment_strategy: "reduce", treatment_plan: "Raise the racks",
      control_owner_id: @owner.company_user.id, residual_likelihood: 2, residual_impact: 3, control_rationale: "Racks above flood line" } }
    assert risk.reload.treatment_submitted?
    assert_equal 6, risk.residual_score
    assert Notification.exists?(recipient: @rm, kind: "risk_treatment_submitted")
    assert Notification.exists?(recipient: @admin, kind: "risk_treatment_submitted")
    assert_not Notification.exists?(recipient: @qm, kind: "risk_treatment_submitted")

    post dashboard_submit_treatment_task_path(risk), params: { risk: { treatment_plan: "Changed" } }
    assert_equal "Raise the racks", risk.reload.treatment_plan, "no edits while under review"

    sign_in @rm
    assert WorkQueue.new(user: @rm, company: @company).items.any? { |i| i.reason == I18n.t("work_queue.reasons.risk_treatment_review") }
    get dashboard_risk_management_path(risk)
    assert_select "form[action=?]", dashboard_accept_risk_treatment_path(risk)
    post dashboard_return_risk_treatment_path(risk), params: { reason: "" }
    assert risk.reload.treatment_submitted?, "a reason is required"
    post dashboard_return_risk_treatment_path(risk), params: { reason: "Add a pump" }
    assert risk.reload.treatment_returned?
    assert_equal "Add a pump", risk.treatment_return_reason
    assert Notification.exists?(recipient: @owner, kind: "risk_treatment_returned")

    sign_in @owner
    get dashboard_treatment_task_path(risk)
    assert_includes response.body, "Add a pump"
    post dashboard_submit_treatment_task_path(risk), params: { risk: { treatment_plan: "Raise the racks and add a pump" } }
    assert risk.reload.treatment_submitted?
    assert_nil risk.treatment_return_reason

    sign_in @admin
    post dashboard_accept_risk_treatment_path(risk)
    assert risk.reload.treatment_accepted?
    assert_equal @admin, risk.treatment_reviewed_by
    assert Notification.exists?(recipient: @owner, kind: "risk_treatment_accepted")
    assert_nil risk.accepted_at, "accepting the treatment is not accepting the exposure"
  end

  test "nobody reviews their own treatment and the quality manager only reads" do
    sign_in @admin
    risk = create_risk(owner: @rm)
    sign_in @rm
    post dashboard_submit_treatment_task_path(risk), params: { risk: { treatment_plan: "Plan" } }
    assert risk.reload.treatment_submitted?
    post dashboard_accept_risk_treatment_path(risk)
    assert risk.reload.treatment_submitted?, "the owner cannot accept their own treatment"
    assert_not WorkQueue.new(user: @rm, company: @company).items.any? { |i| i.reason == I18n.t("work_queue.reasons.risk_treatment_review") }

    sign_in @qm
    get dashboard_risk_management_path(risk)
    assert_response :success
    assert_select "form[action=?]", dashboard_accept_risk_treatment_path(risk), count: 0
    post dashboard_accept_risk_treatment_path(risk)
    assert risk.reload.treatment_submitted?
    get dashboard_edit_risk_path(risk)
    assert_response :redirect
  end

  test "an accepted treatment goes back to the owner once its review date passes" do
    sign_in @rm
    risk = create_risk(owner: @owner)
    risk.update!(treatment_plan: "Plan", treatment_state: "treatment_accepted", next_review_on: Date.current - 1)
    assert risk.treatment_with_owner?
    sign_in @owner
    post dashboard_submit_treatment_task_path(risk), params: { risk: { treatment_plan: "Plan, reviewed" } }
    assert risk.reload.treatment_submitted?
  end

  test "only the owner opens the treatment task" do
    sign_in @rm
    risk = create_risk(owner: @owner)
    other = person("other", :company_viewer)
    sign_in other
    get dashboard_treatment_task_path(risk)
    assert_redirected_to dashboard_overview_path
  end
end
