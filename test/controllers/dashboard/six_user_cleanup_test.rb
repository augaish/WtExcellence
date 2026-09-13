require "test_helper"

# Six-user test F04, F05, E04: the verifier asks for corrections instead of
# editing; a risk manager reads the Library without write controls and gets a
# clean refusal; policy history names who acted; Arabic times say ص/م.
class Dashboard::SixUserCleanupTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!
    @company = Company.create!(name: "Clean Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @admin = create_user("admin", CompanyUser::ROLES[:company_admin])
    @qm = create_user("qm", CompanyUser::ROLES[:company_quality_manager])
    @contributor = create_user("contrib", CompanyUser::ROLES[:company_contributor])
    @risk_manager = create_user("rm", CompanyUser::ROLES[:company_risk_manager])
  end

  def create_user(prefix, role)
    user = User.create!(email: "#{prefix}-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: prefix.humanize, is_active: true)
    CompanyUser.create!(company: @company, user: user, role: role)
    user
  end

  test "the verifier reads the record and sends it to the owner for correction; history names the actor" do
    record = @company.pp_records.create!(record_type: "policy", title_en: "Evidence Policy", description: "x",
      owner_user: @qm, verifier_user: @contributor)

    sign_in @contributor
    get dashboard_documenter_record_path(record)
    assert_select "a[href=?]", dashboard_pp_record_path(record), text: I18n.t("documenter.actions.check_form")
    assert_select "a[href=?]", edit_dashboard_pp_record_path(record), 0
    assert_select "form[action=?]", dashboard_documenter_request_correction_path(record)

    post dashboard_documenter_request_correction_path(record), params: { reason: "" }
    assert_equal 0, record.stage_tasks.count, "a reason is required"

    post dashboard_documenter_request_correction_path(record), params: { reason: "The scope is missing" }
    task = record.stage_tasks.sole
    assert_equal [ @qm, @contributor, "The scope is missing" ], [ task.user, task.assigned_by, task.note ]
    assert Notification.exists?(recipient: @qm, kind: "record_correction_requested")

    post dashboard_documenter_advance_record_path(record)
    get dashboard_documenter_record_path(record)
    assert_includes response.body, @contributor.name, "the history names who verified"
  end

  test "a risk manager reads the Library from the menu without write controls and a write is refused cleanly" do
    sign_in @risk_manager
    get dashboard_overview_path
    assert_select "a[href=?]", library_path

    get library_path
    assert_response :success
    assert_select "button", text: /#{I18n.t('create_new_folder')}/, count: 0
    assert_select "button", text: /#{I18n.t('upload_document')}/, count: 0

    post create_folder_path, params: { folder: { name: "Nope" } }.to_json,
      headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
    assert_response :forbidden
    assert_equal false, response.parsed_body["success"]
    assert_not Folder.exists?(company_id: @company.id, name: "Nope")
  end

  test "Arabic times are written with ص and م, not AM and PM" do
    formatted = I18n.with_locale(:ar) { I18n.l(Time.zone.parse("2026-09-13 10:56"), format: :long) }
    assert_includes formatted, "ص"
    assert_not_includes formatted, "AM"
  end
end
