require "test_helper"

# F09 and F11 are JavaScript behaviours, so the tests here guard the server-side
# contract each fix depends on: the markup the scripts read and write.
class Dashboard::CapaUiDefectsTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!

    @company = Company.create!(name: "Capa Co #{SecureRandom.hex(4)}", license_seats: 10, credits: 50, is_active: true)
    @admin = User.create!(email: "capa-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: "Capa Admin", is_active: true)
    CompanyUser.create!(company: @company, user: @admin, role: CompanyUser::ROLES[:company_admin])
    @capa = Capa.create!(company: @company, title: "QA CAPA", priority: "medium", status: "Open",
      description: "A synthetic CAPA for the interface tests.", source: "audit",
      created_by_id: @admin.id)
  end

  # F09 — the modal set the native value of a Choices-backed select, which does
  # not update what the widget displays.
  test "the selects the edit modal populates are Choices-backed" do
    sign_in @admin
    get dashboard_capa_management_show_path(@capa)

    assert_response :success
    # The rows are built client-side, but the modal itself is server-rendered.
    # The fix depends on these being Choices targets, so that assigning a value
    # is not enough on its own.
    assert_select "select[data-field=?][data-choices-select-target=?]", "priority", "select"
    assert_select "select[data-field=?][data-choices-select-target=?]", "source", "select"
  end

  # F11 — the button's state is server-rendered, so the script needs to know
  # whether it may change it.
  test "the generate actions button says why it is disabled" do
    sign_in @admin
    get dashboard_capa_management_show_path(@capa)

    assert_response :success
    assert_select "#generateActionsButton[data-role-disabled=?]", "false"
    assert_select "#generateActionsButton[data-root-cause-ready=?]", "false"
    assert_select "#generateActionsButton[disabled]"
  end

  test "the button is enabled by the server once a root cause exists" do
    questionnaire = @capa.build_questionnaire(root_cause: "Recovery testing had lapsed.")
    questionnaire.save!

    sign_in @admin
    get dashboard_capa_management_show_path(@capa.reload)

    assert_select "#generateActionsButton[data-root-cause-ready=?]", "true"
    assert_select "#generateActionsButton[disabled]", count: 0
  end
end
