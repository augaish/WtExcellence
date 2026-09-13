require "test_helper"

# Six-user test E01: the contributor submits, the quality manager decides.
class Dashboard::CapaActionHandoffTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!
    @company = Company.create!(name: "Handoff Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @qm = create_user("qm", CompanyUser::ROLES[:company_quality_manager])
    @contributor = create_user("contrib", CompanyUser::ROLES[:company_contributor])
    @capa = Capa.create!(company: @company, title: "Late supplier", description: "x", source: "audit", status: :assigned, created_by: @qm)
    @action = @capa.capa_actions.create!(title: "Prepare evidence", action_type: "corrective", status: "started", due_date: Date.new(2026, 9, 15))
    CapaAssignment.create!(capa: @capa, company_user: @contributor.company_user)
    CapaActionAssignment.create!(capa_action: @action, company_user: @contributor.company_user)
  end

  def create_user(prefix, role)
    user = User.create!(email: "#{prefix}-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: prefix.humanize, is_active: true)
    CompanyUser.create!(company: @company, user: user, role: role)
    user
  end

  test "submit, changes requested, resubmit, accept: the deadline survives and everyone is told" do
    sign_in @contributor
    get dashboard_capa_action_show_path(@capa, @action)
    assert_select "form[action=?]", dashboard_submit_capa_action_review_path(@capa, @action)

    post dashboard_submit_capa_action_review_path(@capa, @action), params: { note: "Evidence attached" }
    assert_equal "ready_for_review", @action.reload.status
    assert_equal "Evidence attached", @action.comments.last.body
    assert Notification.exists?(recipient: @qm, kind: "capa_action_submitted")

    sign_in @qm
    get dashboard_overview_path
    assert_includes response.body, I18n.t("work_queue.reasons.action_to_review")
    get dashboard_capa_action_show_path(@capa, @action)
    assert_select "form[action=?]", dashboard_review_capa_action_path(@capa, @action)

    post dashboard_review_capa_action_path(@capa, @action), params: { outcome: "changes_requested", reason: "" }
    assert_equal "ready_for_review", @action.reload.status, "a reason is required"

    post dashboard_review_capa_action_path(@capa, @action), params: { outcome: "changes_requested", reason: "Add the signed receipt" }
    assert_equal "changes_requested", @action.reload.status
    assert Notification.exists?(recipient: @contributor, kind: "capa_action_changes_requested")

    sign_in @contributor
    get dashboard_overview_path
    assert_includes response.body, CGI.escapeHTML(I18n.t("work_queue.reasons.action_changes_requested"))
    post dashboard_submit_capa_action_review_path(@capa, @action)
    assert_equal "ready_for_review", @action.reload.status

    sign_in @qm
    post dashboard_review_capa_action_path(@capa, @action), params: { outcome: "done" }
    @action.reload
    assert_equal [ "done", Date.new(2026, 9, 15) ], [ @action.status, @action.due_date ]
    assert Notification.exists?(recipient: @contributor, kind: "capa_action_accepted")
    assert AuditLog.exists?(entity_id: @action.id, action: "ACCEPT_CAPA_ACTION")
  end

  test "only the assignee submits and only the manager reviews" do
    other = create_user("other", CompanyUser::ROLES[:company_contributor])
    sign_in other
    post dashboard_submit_capa_action_review_path(@capa, @action)
    assert_equal "started", @action.reload.status

    sign_in @contributor
    post dashboard_review_capa_action_path(@capa, @action), params: { outcome: "done" }
    assert_equal "started", @action.reload.status
  end
end
