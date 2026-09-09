require "test_helper"

# "Update existing": a published record is read-only; its next version is a
# fresh draft carrying everything forward except the reason for change.
class Dashboard::RecordVersionsTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!
    @company = Company.create!(name: "Ver #{SecureRandom.hex(4)}", license_seats: 10, credits: 50, is_active: true)

    @admin = User.create!(email: "ver-admin-#{SecureRandom.hex(4)}@example.com",
      password: "password123", password_confirmation: "password123", name: "Admin", is_active: true)
    CompanyUser.create!(company: @company, user: @admin, role: CompanyUser::ROLES[:company_admin])

    @viewer = User.create!(email: "ver-viewer-#{SecureRandom.hex(4)}@example.com",
      password: "password123", password_confirmation: "password123", name: "Viewer", is_active: true)
    CompanyUser.create!(company: @company, user: @viewer, role: CompanyUser::ROLES[:company_viewer])

    @hr = @company.org_units.create!(name_en: "Human Resources", level: 1, code: "HR")
    @policy = @company.pp_records.create!(record_type: "policy", title_en: "Leave policy", scope: "All staff",
      owner_org_unit: @hr, current_stage: "s5_published")
  end

  test "a published record cannot be edited in place" do
    sign_in @admin
    patch dashboard_pp_record_path(@policy), params: { pp_record: { title_en: "Changed" } }

    assert_redirected_to dashboard_pp_record_path(@policy)
    assert_equal "Leave policy", @policy.reload.title_en
  end

  test "opening the next version copies the content, bumps the code and asks for the reason" do
    sign_in @admin

    assert_difference -> { @company.pp_records.count }, 1 do
      post open_next_version_dashboard_pp_record_path(@policy)
    end

    draft = @policy.reload.next_version
    assert_redirected_to edit_dashboard_pp_record_path(draft)
    assert_equal 2, draft.version_number
    assert_equal "POL-HR-001-V2", draft.code
    assert_equal "All staff", draft.scope
    assert_equal "s1_verify", draft.stage_key, "a new version starts its flow from the beginning"
    refute draft.completed?

    # Saving without a reason is refused; with one it goes through.
    patch dashboard_pp_record_path(draft), params: { pp_record: { title_en: "Leave policy" } }
    assert_response :unprocessable_entity
    patch dashboard_pp_record_path(draft), params: { pp_record: { change_summary: "Annual leave raised to 30 days" } }
    assert_redirected_to dashboard_pp_record_path(draft)
  end

  test "the old version stays readable for the quality team and hidden from others" do
    sign_in @admin
    post open_next_version_dashboard_pp_record_path(@policy)
    draft = @policy.reload.next_version

    get dashboard_pp_records_path
    assert_select "a[href=?]", dashboard_pp_record_path(draft)
    assert_select "a[href=?]", dashboard_pp_record_path(@policy), count: 0

    get dashboard_pp_records_path(show_versions: "1")
    assert_select "a[href=?]", dashboard_pp_record_path(@policy)

    get dashboard_pp_record_path(@policy)
    assert_response :success
    assert_select "body", text: /#{Regexp.escape(I18n.t('pp_records.superseded_banner', version: 1))}/

    sign_out @admin
    sign_in @viewer
    get dashboard_pp_record_path(@policy)
    assert_redirected_to dashboard_pp_record_path(draft)
  end

  test "a second update on the same version is refused" do
    sign_in @admin
    post open_next_version_dashboard_pp_record_path(@policy)
    assert_no_difference -> { @company.pp_records.count } do
      post open_next_version_dashboard_pp_record_path(@policy)
    end
  end
end
