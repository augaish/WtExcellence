require "test_helper"

class Dashboard::DocumenterControllerTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!

    @company = Company.create!(name: "Doc Co #{SecureRandom.hex(4)}", license_seats: 10, credits: 50, is_active: true)

    @admin = create_user("doc-admin", CompanyUser::ROLES[:company_admin])
    @contributor = create_user("doc-contrib", CompanyUser::ROLES[:company_contributor])

    @unit = @company.org_units.create!(name_en: "Finance", level: 1)
    @record = @company.pp_records.create!(record_type: "policy", title_en: "Data Policy",
      code: "POL-01", current_stage: "s1_verify", stage_entered_at: Time.current)
  end

  def create_user(prefix, role)
    user = User.create!(email: "#{prefix}-#{SecureRandom.hex(4)}@example.com",
      password: "password123", password_confirmation: "password123", name: prefix, is_active: true)
    CompanyUser.create!(company: @company, user: user, role: role)
    user
  end

  test "the worklist renders one screen per phase" do
    sign_in @admin
    get dashboard_documenter_path

    assert_response :success
    PpStage::PHASES.each do |phase|
      assert_select "a[href=?]", dashboard_documenter_path(phase: phase)
    end
  end

  test "records appear under the stage they are sitting in" do
    sign_in @admin
    get dashboard_documenter_path(phase: "inventory")

    assert_response :success
    assert_select "body", text: /Data Policy/
    assert_includes response.body, PpStage.label("s1_verify")
  end

  test "the header checkbox is a real toggle wired to the bulk controller" do
    sign_in @admin
    get dashboard_documenter_path(phase: "inventory")

    assert_response :success
    # A true toggle: bound to change, not a one-way "select everything" click.
    assert_select "input[type=checkbox][data-bulk-select-target=header][data-action=?]",
      "change->bulk-select#toggleAll"
  end

  test "bulk advance moves the selected records forward" do
    sign_in @admin
    other = @company.pp_records.create!(record_type: "policy", title_en: "Second",
      current_stage: "s1_verify", stage_entered_at: Time.current)

    post dashboard_documenter_advance_path, params: {
      record_ids: [ @record.id, other.id ], phase: "inventory"
    }

    assert_equal "s1_approved", @record.reload.stage_key
    assert_equal "s1_approved", other.reload.stage_key
  end

  test "bulk advance with nothing selected says so" do
    sign_in @admin
    post dashboard_documenter_advance_path, params: { record_ids: [], phase: "inventory" }

    assert_redirected_to dashboard_documenter_path(phase: "inventory")
    assert_match(/select at least one/i, flash[:alert].to_s)
  end

  # The server recomputes the destination; it never trusts the client.
  test "a contributor cannot bulk advance someone else's record" do
    sign_in @contributor
    post dashboard_documenter_advance_path, params: { record_ids: [ @record.id ], phase: "inventory" }

    assert_equal "s1_verify", @record.reload.stage_key
  end

  test "saving the intersections answer routes the record" do
    sign_in @admin
    @record.update!(current_stage: "s2_confirmation")

    patch dashboard_documenter_intersections_path(@record), params: {
      has_intersections: "true", org_unit_ids: [ @unit.id ], phase: "preparation"
    }

    assert @record.reload.has_intersections?
    # The stakeholder chain is pre-seeded from the named units.
    assert_equal 1, @record.stage_approvals.for_stage("s2_stakeholders").count

    post dashboard_documenter_advance_path, params: { record_ids: [ @record.id ], phase: "preparation" }
    assert_equal "s2_stakeholders", @record.reload.stage_key
  end

  test "answering no to intersections skips stakeholder review" do
    sign_in @admin
    @record.update!(current_stage: "s2_confirmation")

    patch dashboard_documenter_intersections_path(@record), params: { has_intersections: "false", phase: "preparation" }
    post dashboard_documenter_advance_path, params: { record_ids: [ @record.id ], phase: "preparation" }

    assert_equal "s2_final", @record.reload.stage_key
  end

  test "an approval chain blocks the move until every unit responds" do
    sign_in @admin
    @record.update!(current_stage: "s4_final")

    post dashboard_documenter_add_approval_path(@record), params: {
      org_unit_id: @unit.id, stage_key: "s4_final", phase: "approval"
    }
    approval = @record.stage_approvals.for_stage("s4_final").first
    assert approval.requested_at.present?, "requested_at is stamped by the system"

    post dashboard_documenter_advance_path, params: { record_ids: [ @record.id ], phase: "approval" }
    assert_equal "s4_final", @record.reload.stage_key, "must not move while an approval is outstanding"

    patch dashboard_documenter_receive_approval_path(approval_id: approval.id), params: { phase: "approval" }
    assert approval.reload.received_at.present?, "received_at is stamped by the system"

    post dashboard_documenter_advance_path, params: { record_ids: [ @record.id ], phase: "approval" }
    assert_equal "s5_toPublish", @record.reload.stage_key
  end

  test "returning a record requires a reason and records it" do
    sign_in @admin
    @record.update!(current_stage: "s2_final")

    post dashboard_documenter_return_path, params: {
      record_id: @record.id, stage_key: "s2_prep", reason: "Scope section missing", phase: "preparation"
    }

    assert_equal "s2_prep", @record.reload.stage_key
    assert_equal "Scope section missing", @record.stage_transitions.last.reason
  end

  test "returning without a reason is refused" do
    sign_in @admin
    @record.update!(current_stage: "s2_final")

    post dashboard_documenter_return_path, params: {
      record_id: @record.id, stage_key: "s2_prep", reason: "", phase: "preparation"
    }

    assert_equal "s2_final", @record.reload.stage_key
  end

  test "a contributor cannot return a record" do
    sign_in @contributor
    @record.update!(current_stage: "s2_final")

    post dashboard_documenter_return_path, params: {
      record_id: @record.id, stage_key: "s2_prep", reason: "trying", phase: "preparation"
    }

    assert_equal "s2_final", @record.reload.stage_key
  end

  test "reopening a closed record creates a new version and leaves the old one" do
    sign_in @admin
    @record.update!(current_stage: "s5_closed", version_label: "v1.0")

    assert_difference -> { @company.pp_records.count }, 1 do
      post dashboard_documenter_reopen_path(@record), params: { phase: "publishing" }
    end

    new_version = @company.pp_records.order(:created_at).last
    assert_equal 2, new_version.version_number
    assert_equal @record.id, new_version.previous_version_id
    assert_equal PpStage::FIRST_KEY, new_version.stage_key
    # The published version is untouched.
    assert_equal "s5_closed", @record.reload.stage_key
  end

  test "an open record cannot be reopened" do
    sign_in @admin

    assert_no_difference -> { @company.pp_records.count } do
      post dashboard_documenter_reopen_path(@record), params: { phase: "inventory" }
    end
  end

  test "settings renders every stage target and the working week" do
    sign_in @admin
    get dashboard_documenter_settings_path

    assert_response :success
    PpStage::KEYS.each do |key|
      assert_select "input[name=?]", "targets[#{key}]"
    end
    assert_select "input[name='weekend_days[]']"
  end

  test "saving settings stores targets and the weekend" do
    sign_in @admin

    patch dashboard_update_documenter_settings_path, params: {
      targets: { "s2_prep" => "14", "s4_final" => "7" },
      weekend_days: [ "0", "6" ]
    }

    assert_equal 14, PpStageTarget.days_for(@company.reload, "s2_prep")
    assert_equal 7, PpStageTarget.days_for(@company, "s4_final")
    assert_equal [ 0, 6 ], @company.reload.weekend_days
  end

  test "holidays can be added and removed" do
    sign_in @admin

    assert_difference -> { @company.company_holidays.count }, 1 do
      post dashboard_documenter_holidays_path, params: {
        name: "Eid", start_date: "2026-04-01", end_date: "2026-04-05"
      }
    end

    holiday = @company.company_holidays.last
    assert_difference -> { @company.company_holidays.count }, -1 do
      delete dashboard_documenter_holiday_path(holiday_id: holiday.id)
    end
  end

  test "a contributor cannot open Documenter settings" do
    sign_in @contributor
    get dashboard_documenter_settings_path

    assert_redirected_to dashboard_documenter_path
  end

  test "a late record is flagged against its stage target" do
    sign_in @admin
    @company.pp_stage_targets.create!(stage_key: "s1_verify", target_days: 1)
    @record.update!(stage_entered_at: 30.days.ago)

    get dashboard_documenter_path(phase: "inventory")

    assert_response :success
    assert_match(/Late by/, response.body)
  end
end
