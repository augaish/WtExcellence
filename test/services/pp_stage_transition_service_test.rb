require "test_helper"

class PpStageTransitionServiceTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Trans Co #{SecureRandom.hex(4)}", license_seats: 10, is_active: true)

    @admin = create_user("admin", CompanyUser::ROLES[:company_admin])
    @qm = create_user("qm", CompanyUser::ROLES[:company_quality_manager])
    @contributor = create_user("contrib", CompanyUser::ROLES[:company_contributor])
    @owner = create_user("owner", CompanyUser::ROLES[:company_contributor])

    @record = @company.pp_records.create!(
      record_type: "policy", title_en: "Data Policy",
      owner_user: @owner, current_stage: PpStage::FIRST_KEY, stage_entered_at: Time.current
    )
    @unit = @company.org_units.create!(name_en: "Finance", level: 1)
  end

  def create_user(prefix, role)
    user = User.create!(email: "#{prefix}-#{SecureRandom.hex(4)}@example.com",
      password: "password123", password_confirmation: "password123", name: prefix, is_active: true)
    CompanyUser.create!(company: @company, user: user, role: role)
    user
  end

  def advance(user: @admin, record: @record)
    PpStageTransitionService.advance(record: record, user: user, company: @company)
  end

  # ---- Forward -----------------------------------------------------------

  test "advancing moves to the computed next stage and records history" do
    advance

    assert_equal "s1_approved", @record.reload.stage_key
    transition = @record.stage_transitions.last
    assert_equal "s1_verify", transition.from_stage
    assert_equal "s1_approved", transition.to_stage
    assert_equal "forward", transition.direction
    assert_equal @admin.id, transition.actor_user_id
  end

  test "advancing stamps the stage clock from the system, not a typed date" do
    before = Time.current
    advance

    assert @record.reload.stage_entered_at >= before
  end

  test "a policy without intersections skips stakeholder review" do
    @record.update!(current_stage: "s2_confirmation", has_intersections: false)
    advance

    assert_equal "s2_final", @record.reload.stage_key
  end

  test "a record with intersections goes through stakeholder review" do
    @record.update!(current_stage: "s2_confirmation", has_intersections: true)
    advance

    assert_equal "s2_stakeholders", @record.reload.stage_key
  end

  test "a procedure goes through the design phase and a policy does not" do
    procedure = @company.pp_records.create!(record_type: "procedure", title_en: "Onboarding", pp_process: level_two_process(@company),
      current_stage: "s2_final", stage_entered_at: Time.current)
    advance(record: procedure)
    assert_equal "s3_design", procedure.reload.stage_key

    @record.update!(current_stage: "s2_final")
    advance
    assert_equal "s4_initial", @record.reload.stage_key
  end

  test "the terminal stage cannot be advanced" do
    @record.update!(current_stage: PpStage::TERMINAL_KEY)

    assert_raises(PpStageTransitionService::InvalidTransition) { advance }
  end

  # ---- Approval chains ---------------------------------------------------

  test "an approval stage cannot be left while a unit has not responded" do
    @record.update!(current_stage: "s4_final")
    @record.stage_approvals.create!(stage_key: "s4_final", org_unit: @unit, requested_at: Time.current)

    assert_raises(PpStageTransitionService::ApprovalsPending) { advance }
    assert_equal "s4_final", @record.reload.stage_key
  end

  test "an approval stage advances once every unit has responded" do
    @record.update!(current_stage: "s4_final")
    approval = @record.stage_approvals.create!(stage_key: "s4_final", org_unit: @unit, requested_at: Time.current)
    approval.update!(received_at: Time.current, received_by: @admin)

    advance

    assert_equal "s5_toPublish", @record.reload.stage_key
  end

  test "an approval stage with no chain yet still requires one" do
    @record.update!(current_stage: "s4_final")

    assert_raises(PpStageTransitionService::ApprovalsPending) { advance }
  end

  # ---- Permissions -------------------------------------------------------

  test "admins, the quality manager and the owner may move a record forward" do
    [ @admin, @qm, @owner ].each do |user|
      record = @company.pp_records.create!(record_type: "policy", title_en: "Doc #{SecureRandom.hex(3)}",
        owner_user: @owner, current_stage: PpStage::FIRST_KEY, stage_entered_at: Time.current)
      assert_nothing_raised { advance(user: user, record: record) }
    end
  end

  test "an unrelated contributor may not move a record forward" do
    assert_raises(PpStageTransitionService::NotPermitted) { advance(user: @contributor) }
    assert_equal PpStage::FIRST_KEY, @record.reload.stage_key
  end

  test "a contributor assigned to the current stage may move it forward" do
    @record.stage_assignees.create!(stage_key: @record.stage_key, user: @contributor)

    assert_nothing_raised { advance(user: @contributor) }
  end

  # ---- Backward ----------------------------------------------------------

  test "returning to an earlier stage requires a reason" do
    @record.update!(current_stage: "s2_final")

    assert_raises(PpStageTransitionService::InvalidTransition) do
      PpStageTransitionService.return_to(record: @record, user: @admin, company: @company,
        stage_key: "s2_prep", reason: "  ")
    end
  end

  test "returning records the reason and the direction" do
    @record.update!(current_stage: "s2_final")

    PpStageTransitionService.return_to(record: @record, user: @admin, company: @company,
      stage_key: "s2_prep", reason: "Missing scope section")

    assert_equal "s2_prep", @record.reload.stage_key
    transition = @record.stage_transitions.last
    assert_equal "backward", transition.direction
    assert_equal "Missing scope section", transition.reason
  end

  test "returning forward is refused" do
    @record.update!(current_stage: "s2_prep")

    assert_raises(PpStageTransitionService::InvalidTransition) do
      PpStageTransitionService.return_to(record: @record, user: @admin, company: @company,
        stage_key: "s2_final", reason: "trying to skip ahead")
    end
  end

  test "returning to a stage that is not on this record's route is refused" do
    @record.update!(current_stage: "s4_initial", record_type: "policy")

    # s3_design belongs to procedures only.
    assert_raises(PpStageTransitionService::InvalidTransition) do
      PpStageTransitionService.return_to(record: @record, user: @admin, company: @company,
        stage_key: "s3_design", reason: "not on route")
    end
  end

  test "the owner may not return a record; that is a separate permission" do
    @record.update!(current_stage: "s2_final")

    assert_raises(PpStageTransitionService::NotPermitted) do
      PpStageTransitionService.return_to(record: @record, user: @owner, company: @company,
        stage_key: "s2_prep", reason: "owner tries to return")
    end
  end

  # ---- Bulk --------------------------------------------------------------

  test "bulk advance moves what it can and reports what it could not" do
    ok = @company.pp_records.create!(record_type: "policy", title_en: "A",
      current_stage: "s1_verify", stage_entered_at: Time.current)
    blocked = @company.pp_records.create!(record_type: "policy", title_en: "B",
      current_stage: "s4_final", stage_entered_at: Time.current)
    blocked.stage_approvals.create!(stage_key: "s4_final", org_unit: @unit, requested_at: Time.current)

    result = PpStageTransitionService.advance_many(records: [ ok, blocked ], user: @admin, company: @company)

    assert_equal [ ok.id ], result.moved.map(&:id)
    assert_equal [ blocked.id ], result.skipped.map(&:id)
    refute result.success?
    assert_equal "s1_approved", ok.reload.stage_key
    assert_equal "s4_final", blocked.reload.stage_key
  end
end
