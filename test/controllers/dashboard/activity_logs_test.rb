require "test_helper"

# Every model leaves a trace; the Activity page reads it; a record shows its own.
class Dashboard::ActivityLogsTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!
    @company = Company.create!(name: "Trail Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @admin = create_user("trail-admin", CompanyUser::ROLES[:company_admin])
    @viewer = create_user("trail-viewer", CompanyUser::ROLES[:company_viewer])
  end

  def create_user(prefix, role)
    user = User.create!(email: "#{prefix}-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: prefix.humanize, is_active: true)
    CompanyUser.create!(company: @company, user: user, role: role)
    user
  end

  test "a change made through the app is logged with the actor, the old and the new value" do
    sign_in @admin
    unit = @company.org_units.create!(name_en: "Quality", level: 1)
    record = @company.pp_records.create!(record_type: "policy", title_en: "HR Policy", description: "x")

    patch dashboard_pp_record_path(record), params: { pp_record: { title_en: "HR Policy v2", owner_org_unit_id: unit.id } }

    entries = AuditLog.where(entity_type: "pp_record", entity_id: record.id, action: "UPDATE_PP_RECORD")
    entry = entries.find { |e| e.payload_json.dig("changes", "title_en") }
    assert entry, "the title change was not logged"
    assert_equal @admin, entry.actor_user
    assert_equal @company, entry.company
    assert_equal [ "HR Policy", "HR Policy v2" ], entry.payload_json["changes"]["title_en"]
    assert_equal "HR Policy v2", entry.payload_json["label"]
  end

  test "a nested row is filed under its parent's company, and a delete is logged" do
    sign_in @admin
    record = @company.pp_records.create!(record_type: "policy", title_en: "HR Policy", description: "x")
    post dashboard_pp_record_clauses_path(record), params: { pp_record_clause: { title: "Purpose", body: "Why" } }
    clause = record.clauses.sole
    assert AuditLog.exists?(company: @company, entity_type: "pp_record_clause", entity_id: clause.id, action: "CREATE_PP_RECORD_CLAUSE")

    delete dashboard_pp_record_path(record)
    assert AuditLog.exists?(company: @company, entity_type: "pp_record", entity_id: record.id, action: "DELETE_PP_RECORD")
  end

  test "nothing is logged without someone acting, and secrets are never stored" do
    Thread.current[:current_user] = nil
    record = @company.pp_records.create!(record_type: "policy", title_en: "Quiet", description: "x")
    assert_not AuditLog.exists?(entity_id: record.id)

    Thread.current[:current_user] = @admin
    old_name = @admin.name
    @admin.update!(password: "another-secret-1", password_confirmation: "another-secret-1", name: "Renamed")
    entry = AuditLog.where(entity_type: "user", entity_id: @admin.id, action: "UPDATE_USER").last
    assert_equal [ old_name, "Renamed" ], entry.payload_json["changes"]["name"]
    assert_nil entry.payload_json["changes"]["encrypted_password"]
    assert_not_includes entry.payload_json.to_json, "another-secret-1"
  ensure
    Thread.current[:current_user] = nil
  end

  test "the Activity page lists entries, filters them, exports them, and is closed to viewers" do
    sign_in @admin
    record = @company.pp_records.create!(record_type: "policy", title_en: "Filtered Policy", description: "x")
    patch dashboard_pp_record_path(record), params: { pp_record: { title_en: "Filtered Policy 2" } }
    unit = @company.org_units.create!(name_en: "Ops", level: 1)
    patch dashboard_org_unit_path(unit), params: { org_unit: { name_en: "Operations" } }

    get dashboard_activity_path
    assert_response :success
    assert_select "a[href=?]", dashboard_activity_path
    assert_includes response.body, I18n.t("activity.verbs.update", record: I18n.t("activity.entities.pp_record"))
    assert_includes response.body, I18n.t("activity.verbs.update", record: I18n.t("activity.entities.org_unit"))

    get dashboard_activity_path(module: "pp", verb: "update")
    assert_includes response.body, "Filtered Policy 2"
    assert_not_includes response.body, "Operations"

    get dashboard_activity_path(q: "Operations")
    assert_includes response.body, "Operations"
    assert_not_includes response.body, "Filtered Policy 2"

    get dashboard_activity_export_path(module: "pp")
    assert_response :success
    sheet = Roo::Excelx.new(StringIO.new(response.body), file_warning: :ignore).sheet("Activity")
    assert_includes sheet.column(6), "Filtered Policy 2"

    sign_in @viewer
    get dashboard_activity_path
    assert_redirected_to dashboard_general_settings_path
    get dashboard_general_settings_path
    assert_select "a[href=?]", dashboard_activity_path, 0
  end

  test "a record page shows its own history" do
    sign_in @admin
    record = @company.pp_records.create!(record_type: "policy", title_en: "Seen Policy", description: "x")
    patch dashboard_pp_record_path(record), params: { pp_record: { title_en: "Seen Policy 2" } }

    get dashboard_pp_record_path(record)
    assert_select "details summary", text: /#{I18n.t('activity.history')}/
    assert_includes response.body, I18n.t("activity.verbs.update", record: I18n.t("activity.entities.pp_record"))
  end
end

class ActivityFoldingTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!
    @company = Company.create!(name: "Fold Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @super_admin = User.create!(email: "fold-root-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: "Root", role: "super_admin", is_active: true)
  end

  test "an action the app describes itself is one entry, carrying the changed values" do
    sign_in @super_admin
    email = "folded-#{SecureRandom.hex(3)}@example.com"
    post dashboard_create_invitation_path, params: { name: "Folded Person", email: email, company_id: @company.id, company_role: "company_viewer" }

    user = User.find_by(email: email)
    entries = AuditLog.where(entity_type: "user", entity_id: user.id)
    assert_equal [ "CREATE_USER_INVITATION" ], entries.map(&:action), "the plain 'User created' entry is folded into the invitation"
    assert_equal "Folded Person", entries.sole.payload_json["user_name"]
  end
end
