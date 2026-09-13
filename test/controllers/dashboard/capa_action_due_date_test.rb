require "test_helper"

# Changing only an action's status keeps its deadline.
class Dashboard::CapaActionDueDateTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!
    @company = Company.create!(name: "Due Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @qm = User.create!(email: "due-qm-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: "QM", is_active: true)
    @cu = CompanyUser.create!(company: @company, user: @qm, role: CompanyUser::ROLES[:company_quality_manager])
    @capa = Capa.create!(company: @company, title: "Late supplier", description: "x", source: "internal_audit", status: :open, created_by: @qm)
    @action = @capa.capa_actions.create!(title: "Prepare evidence", action_type: "corrective", status: "started", due_date: Date.new(2026, 9, 15))
  end

  test "a status-only update keeps the due date; a blank due date sent on purpose clears it" do
    sign_in @qm
    patch dashboard_update_capa_action_path(capa_id: @capa.id, id: @action.id), params: { capa_action: { status: "done" } }, as: :json
    assert_response :success
    assert_equal [ "done", Date.new(2026, 9, 15) ], [ @action.reload.status, @action.due_date ]

    patch dashboard_update_capa_action_path(capa_id: @capa.id, id: @action.id), params: { capa_action: { due_date: "" } }, as: :json
    assert_nil @action.reload.due_date
  end
end
