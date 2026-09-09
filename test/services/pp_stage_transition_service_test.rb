require "test_helper"

class PpStageTransitionServiceTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Flow Co #{SecureRandom.hex(4)}", license_seats: 10, is_active: true)
    @admin = user("admin", CompanyUser::ROLES[:company_admin])
    @pp_manager = user("ppm", CompanyUser::ROLES[:company_quality_manager], pp_manager: true)
    @plain_qm = user("qm", CompanyUser::ROLES[:company_quality_manager])
    @head = user("head", CompanyUser::ROLES[:company_contributor])
    @verifier = user("verifier", CompanyUser::ROLES[:company_contributor])
    @someone = user("someone", CompanyUser::ROLES[:company_contributor])

    @unit = @company.org_units.create!(name_en: "Finance", level: 1, head_user: @head)
    @record = @company.pp_records.create!(record_type: "policy", title_en: "Spending policy",
      owner_org_unit: @unit, verifier_user: @verifier)
  end

  def advance(record: @record, user: @admin, **opts)
    PpStageTransitionService.advance(record: record, user: user, company: @company, **opts)
  end

  test "a new record starts at Data Verification with the clock running" do
    assert_equal "s1_verify", @record.stage_key
    assert @record.stage_entered_at.present?
  end

  test "the verifier moves it on; a bystander cannot" do
    assert_raises(PpStageTransitionService::NotPermitted) { advance(user: @someone) }
    advance(user: @verifier)
    assert_equal "s1_approved", @record.reload.stage_key
  end

  test "a P&P Manager acts everywhere a manager acts; a quality manager without the flag does not" do
    @record.update!(current_stage: "s1_approved")
    assert_raises(PpStageTransitionService::NotPermitted) { advance(user: @plain_qm) }
    advance(user: @pp_manager)
    assert_equal "s2_prep", @record.reload.stage_key
  end

  test "the unit head approves the draft; open work handed out must come back first" do
    @record.update!(current_stage: "s2_prep")
    task = @record.stage_tasks.create!(stage_key: "s2_prep", user: @someone, assigned_by: @head, assigned_at: Time.current)
    assert_raises(PpStageTransitionService::WorkOutstanding) { advance(user: @head) }

    task.submit!
    advance(user: @head)
    assert_equal "s2_draftReview", @record.reload.stage_key
  end

  test "stakeholder review waits for every unit, and may be skipped only when nobody was asked" do
    @record.update!(current_stage: "s2_stakeholders")
    assert_raises(PpStageTransitionService::ApprovalsPending) { advance }
    advance(skip_stakeholders: true)
    assert_equal "s4_final", @record.reload.stage_key

    @record.update!(current_stage: "s2_stakeholders")
    approval = @record.stage_approvals.create!(stage_key: "s2_stakeholders", org_unit: @unit, requested_at: Time.current)
    assert_raises(PpStageTransitionService::ApprovalsPending) { advance(skip_stakeholders: true) }
    approval.answer!("approved", by: @head)
    advance
    assert_equal "s4_final", @record.reload.stage_key
  end

  test "final approval cannot be skipped" do
    @record.update!(current_stage: "s4_final")
    assert_raises(PpStageTransitionService::ApprovalsPending) { advance(skip_stakeholders: true) }
  end

  test "a procedure passes through design; a policy does not" do
    procedure = @company.pp_records.create!(record_type: "procedure", title_en: "Pay a supplier",
      owner_org_unit: @unit, pp_process: level_two_process(@company), current_stage: "s2_stakeholders")
    advance(record: procedure, skip_stakeholders: true)
    assert_equal "s3_design", procedure.reload.stage_key

    @record.update!(current_stage: "s2_stakeholders")
    advance(skip_stakeholders: true)
    assert_equal "s4_final", @record.reload.stage_key
  end

  test "the terminal stage is reached through publishing only" do
    @record.update!(current_stage: "s5_toPublish")
    assert_raises(PpStageTransitionService::InvalidTransition) { advance }
    PpStageTransitionService.new(record: @record, user: @admin, company: @company).publish!
    assert_equal "s5_published", @record.reload.stage_key
    assert_nil @record.next_stage_key
  end

  test "returning needs a manager, a reason, and an earlier stage on the route" do
    @record.update!(current_stage: "s2_draftReview")
    service = ->(user, key, reason) { PpStageTransitionService.return_to(record: @record, user: user, company: @company, stage_key: key, reason: reason) }

    assert_raises(PpStageTransitionService::NotPermitted) { service.call(@head, "s2_prep", "fix") }
    assert_raises(PpStageTransitionService::InvalidTransition) { service.call(@pp_manager, "s2_prep", "") }
    assert_raises(PpStageTransitionService::InvalidTransition) { service.call(@pp_manager, "s4_final", "later") }

    service.call(@pp_manager, "s2_prep", "Clauses 2 and 3 need work")
    @record.reload
    assert_equal "s2_prep", @record.stage_key
    transition = @record.stage_transitions.last
    assert_equal "backward", transition.direction
    assert_equal "Clauses 2 and 3 need work", transition.reason
  end

  private

  def user(tag, role, pp_manager: false)
    u = User.create!(email: "#{tag}-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: tag.capitalize, is_active: true)
    CompanyUser.create!(company: @company, user: u, role: role, pp_manager: pp_manager)
    u
  end
end
