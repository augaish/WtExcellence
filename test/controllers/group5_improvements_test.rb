require "test_helper"

# Test team improvements: leave cover, Documenter filters, glossary picker.
class Group5ImprovementsTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!
    @company = Company.create!(name: "G5 Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @qm = create_user("qm", CompanyUser::ROLES[:company_quality_manager])
    @qm.company_user.update!(pp_manager: true)
    @verifier = create_user("verifier", CompanyUser::ROLES[:company_contributor])
    @cover = create_user("cover", CompanyUser::ROLES[:company_contributor])
  end

  def create_user(prefix, role)
    user = User.create!(email: "#{prefix}-#{SecureRandom.hex(4)}@example.com", password: "Password1234",
      password_confirmation: "Password1234", name: prefix.humanize, is_active: true)
    CompanyUser.create!(company: @company, user: user, role: role)
    user
  end

  test "leave cover: the delegate is told, sees the verifier's work and can verify" do
    record = @company.pp_records.create!(record_type: "policy", title_en: "Covered", description: "x", owner_user: @qm, verifier_user: @verifier)

    sign_in @verifier
    patch dashboard_update_delegation_path, params: { user: { delegate_user_id: @cover.id, delegate_from: Date.current, delegate_until: 1.week.from_now.to_date } }
    assert_redirected_to dashboard_general_settings_path
    assert Notification.exists?(recipient: @cover, kind: "delegation_cover_assigned")

    sign_in @cover
    get dashboard_overview_path
    assert_select "a[href=?]", dashboard_documenter_record_path(record)
    get dashboard_general_settings_path
    assert_includes response.body, CGI.escapeHTML(I18n.t("delegation_cover.you_cover", names: @verifier.name))

    post dashboard_documenter_advance_record_path(record)
    assert_equal "s1_approved", record.reload.stage_key

    sign_in @verifier
    patch dashboard_update_delegation_path, params: { user: { delegate_user_id: @cover.id, delegate_from: 2.weeks.ago.to_date, delegate_until: 1.week.ago.to_date } }
    other = @company.pp_records.create!(record_type: "policy", title_en: "Not covered", description: "x", owner_user: @qm, verifier_user: @verifier)
    sign_in @cover
    post dashboard_documenter_advance_record_path(other)
    assert_equal "s1_verify", other.reload.stage_key, "an expired cover grants nothing"
  end

  test "the Documenter worklist filters by unit and type, and the manager moves what is shown" do
    hr = @company.org_units.create!(name_en: "HR", level: 1)
    legal = @company.org_units.create!(name_en: "Legal", level: 1)
    @company.pp_records.create!(record_type: "policy", title_en: "HR Policy", description: "x", owner_org_unit: hr)
    @company.pp_records.create!(record_type: "policy", title_en: "Legal Policy", description: "x", owner_org_unit: legal)
    @company.pp_records.create!(record_type: "form", title_en: "HR Form", scope: "x", owner_org_unit: hr)

    sign_in @qm
    get dashboard_documenter_path(unit_id: hr.id)
    assert_includes response.body, "HR Policy"
    assert_includes response.body, "HR Form"
    assert_not_includes response.body, "Legal Policy"

    get dashboard_documenter_path(unit_id: hr.id, record_type: "policy")
    assert_includes response.body, "HR Policy"
    assert_not_includes response.body, "HR Form"
    assert_select "select[name=unit_id]"
  end

  test "the clause editor offers the company's approved terms" do
    @company.glossary_terms.create!(term_en: "CAPA", definition_en: "Corrective and preventive action")
    record = @company.pp_records.create!(record_type: "policy", title_en: "Terms", description: "x", owner_user: @qm, current_stage: "s2_prep")
    sign_in @qm
    get dashboard_documenter_record_path(record)
    assert_select "select[name=glossary_term] option", text: "CAPA"
    assert_includes response.body, "CAPA: Corrective and preventive action"
  end
end
