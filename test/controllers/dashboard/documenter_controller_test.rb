require "test_helper"

# The Documenter flows, walked the way the product owner described them: each
# stage by the person who acts in it, with the doors that must stay shut.
class Dashboard::DocumenterControllerTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!
    @company = Company.create!(name: "Doc Co #{SecureRandom.hex(4)}", license_seats: 20, credits: 50, is_active: true)

    @admin = create_user("doc-admin", CompanyUser::ROLES[:company_admin])
    @ppm = create_user("doc-ppm", CompanyUser::ROLES[:company_quality_manager], pp_manager: true)
    @head = create_user("doc-head", CompanyUser::ROLES[:company_contributor])
    @reporter = create_user("doc-reporter", CompanyUser::ROLES[:company_contributor])
    @verifier = create_user("doc-verifier", CompanyUser::ROLES[:company_contributor])
    @legal_head = create_user("doc-legal", CompanyUser::ROLES[:company_contributor])
    @contributor = create_user("doc-contrib", CompanyUser::ROLES[:company_contributor])

    @unit = @company.org_units.create!(name_en: "Finance", level: 1, code: "FIN", head_user: @head)
    @legal = @company.org_units.create!(name_en: "Legal", level: 1, code: "LEG", head_user: @legal_head)
    @reporter.update!(org_unit: @unit)

    @record = @company.pp_records.create!(record_type: "policy", title_en: "Data Policy",
      owner_org_unit: @unit, verifier_user: @verifier)
  end

  def create_user(prefix, role, pp_manager: false)
    user = User.create!(email: "#{prefix}-#{SecureRandom.hex(4)}@example.com",
      password: "password123", password_confirmation: "password123", name: prefix, is_active: true)
    CompanyUser.create!(company: @company, user: user, role: role, pp_manager: pp_manager)
    user
  end

  def flow_path = dashboard_documenter_record_path(@record)

  # ---- Worklist ------------------------------------------------------------

  test "the worklist shows each person what needs them, and managers the phases" do
    sign_in @verifier
    get dashboard_documenter_path
    assert_response :success
    assert_select "a[href=?]", flow_path
    assert_select "a[href=?]", dashboard_documenter_path(phase: "inventory"), count: 0

    sign_out @verifier
    sign_in @contributor
    get dashboard_documenter_path
    assert_select "a[href=?]", flow_path, count: 0

    sign_out @contributor
    sign_in @ppm
    get dashboard_documenter_path(phase: "inventory")
    assert_select "a[href=?]", dashboard_documenter_path(phase: "approval")
    assert_select "body", text: /Data Policy/
  end

  # ---- Data Verification → Approved Addition --------------------------------

  test "the verifier checks the form and sends it on; the P&P Manager approves or pushes back" do
    sign_in @verifier
    get flow_path
    assert_select "form[action=?]", dashboard_documenter_advance_record_path(@record)
    post dashboard_documenter_advance_record_path(@record)
    assert_equal "s1_approved", @record.reload.stage_key

    sign_out @verifier
    sign_in @ppm
    post dashboard_documenter_return_path, params: { record_id: @record.id, stage_key: "s1_verify", reason: "Scope missing" }
    assert_equal "s1_verify", @record.reload.stage_key
    assert_equal "Scope missing", @record.stage_transitions.order(:created_at).last.reason

    @record.update!(current_stage: "s1_approved")
    post dashboard_documenter_advance_record_path(@record)
    assert_equal "s2_prep", @record.reload.stage_key
  end

  # ---- Initial Draft Preparation --------------------------------------------

  test "the unit head hands the draft to a reporter, who writes clauses and sends it back" do
    @record.update!(current_stage: "s2_prep")

    sign_in @head
    post dashboard_documenter_assign_task_path(@record), params: { user_id: @reporter.id, note: "Draft by Sunday" }
    task = @record.stage_tasks.open.last
    assert_equal @reporter, task.user
    assert Notification.exists?(recipient: @reporter, kind: "record_task_assigned")

    # The head cannot approve while the work is out.
    post dashboard_documenter_advance_record_path(@record)
    assert_equal "s2_prep", @record.reload.stage_key

    sign_out @head
    sign_in @reporter
    post dashboard_pp_record_clauses_path(@record), params: { pp_record_clause: { title: "Purpose", body: "Why this policy exists" } }
    main = @record.clauses.main.first
    post dashboard_pp_record_clauses_path(@record), params: { pp_record_clause: { parent_id: main.id, title: "Applies to all staff" } }
    assert_equal "1.1", main.children.first.number

    post dashboard_documenter_submit_task_path(@record), params: { note: "Done" }
    assert task.reload.submitted_at.present?

    # A contributor with no task cannot write clauses.
    sign_out @reporter
    sign_in @contributor
    post dashboard_pp_record_clauses_path(@record), params: { pp_record_clause: { title: "Sneaky" } }
    assert_equal 1, @record.clauses.main.count

    sign_out @contributor
    sign_in @head
    post dashboard_documenter_advance_record_path(@record)
    assert_equal "s2_draftReview", @record.reload.stage_key
  end

  test "a unit head can only hand work to their own reporters" do
    @record.update!(current_stage: "s2_prep")
    sign_in @head
    post dashboard_documenter_assign_task_path(@record), params: { user_id: @contributor.id }
    assert_equal 0, @record.stage_tasks.count
  end

  # ---- Initial Draft Review --------------------------------------------------

  test "the P&P Manager reviews clause by clause, can hand it to a team member, and pushes back or approves" do
    @record.update!(current_stage: "s2_draftReview")
    clause = @record.clauses.create!(title: "Purpose", body: "Why")

    sign_in @ppm
    post dashboard_documenter_assign_task_path(@record), params: { user_id: @contributor.id }
    sign_out @ppm

    sign_in @contributor
    post dashboard_pp_record_clause_comments_path(@record, clause), params: { body: "Too vague" }
    assert_equal 1, clause.comments.count
    post dashboard_documenter_submit_task_path(@record)
    sign_out @contributor

    sign_in @ppm
    post dashboard_documenter_return_path, params: { record_id: @record.id, stage_key: "s2_prep", reason: "See comments" }
    assert_equal "s2_prep", @record.reload.stage_key

    @record.update!(current_stage: "s2_draftReview")
    post dashboard_documenter_advance_record_path(@record)
    assert_equal "s2_stakeholders", @record.reload.stage_key
  end

  # ---- Stakeholder Review ----------------------------------------------------

  test "stakeholders answer in their own worklist; colours, sequence groups and rejection" do
    @record.update!(current_stage: "s2_stakeholders")

    sign_in @ppm
    post dashboard_documenter_request_approvals_path(@record), params: { groups: { "1" => [ @legal.id ], "2" => [ @unit.id ] } }
    legal = @record.stage_approvals.find_by(org_unit: @legal)
    finance = @record.stage_approvals.find_by(org_unit: @unit)
    assert legal.turn?
    refute finance.turn?, "group 2 waits for group 1"
    assert Notification.exists?(recipient: @legal_head, kind: "record_approval_requested")
    refute Notification.exists?(recipient: @head, kind: "record_approval_requested")
    sign_out @ppm

    sign_in @legal_head
    get dashboard_documenter_path
    assert_select "a[href=?]", flow_path
    get flow_path
    assert_select "form[action=?]", dashboard_documenter_answer_approval_path(legal)
    patch dashboard_documenter_answer_approval_path(legal), params: { decision: "rejected", comment: "" }
    assert legal.reload.pending?, "rejecting without a comment is refused"
    patch dashboard_documenter_answer_approval_path(legal), params: { decision: "rejected", comment: "Clause 2 conflicts with the law" }
    assert legal.reload.rejected?
    assert_equal "red", legal.status_colour
    sign_out @legal_head

    sign_in @ppm
    get flow_path
    assert_select "form[action=?]", dashboard_documenter_resend_approvals_path(@record, scope: "rejected")
    post dashboard_documenter_resend_approvals_path(@record, scope: "rejected")
    assert legal.reload.pending?
    sign_out @ppm

    sign_in @legal_head
    patch dashboard_documenter_answer_approval_path(legal), params: { decision: "approved" }
    assert finance.reload.turn?, "group 2 is asked once group 1 approved"
    assert Notification.exists?(recipient: @head, kind: "record_approval_requested")
    sign_out @legal_head

    sign_in @head
    patch dashboard_documenter_answer_approval_path(finance), params: { decision: "approved" }
    assert_equal "s4_final", @record.reload.stage_key, "all green moves the record on by itself"
  end

  test "only the unit's head can answer for it" do
    @record.update!(current_stage: "s2_stakeholders")
    approval = @record.stage_approvals.create!(stage_key: "s2_stakeholders", org_unit: @legal, requested_at: Time.current)
    sign_in @contributor
    patch dashboard_documenter_answer_approval_path(approval), params: { decision: "approved" }
    assert approval.reload.pending?
  end

  test "silence past the period counts as approval" do
    @record.update!(current_stage: "s2_stakeholders")
    sign_in @ppm
    post dashboard_documenter_request_approvals_path(@record), params: { org_unit_ids: [ @legal.id ], auto_approve_days: 2 }
    approval = @record.stage_approvals.find_by(org_unit: @legal)
    assert approval.auto_approve_at.present?

    travel 1.day do
      ApprovalAutoApproveJob.perform_now
      assert approval.reload.pending?, "not yet"
    end
    travel 10.days do
      ApprovalAutoApproveJob.perform_now
      assert_equal "auto_approved", approval.reload.decision
      assert_equal "s4_final", @record.reload.stage_key
    end
  end

  test "stakeholder review is skipped only when nobody was asked" do
    @record.update!(current_stage: "s2_stakeholders")
    sign_in @ppm
    post dashboard_documenter_skip_stakeholders_path(@record)
    assert_equal "s4_final", @record.reload.stage_key
  end

  # ---- Final Approval and publishing ------------------------------------------

  test "final approval by the chosen heads, then publishing through a publisher whom the manager confirms" do
    @record.update!(current_stage: "s4_final")
    sign_in @ppm
    post dashboard_documenter_request_approvals_path(@record), params: { org_unit_ids: [ @legal.id ] }
    post dashboard_documenter_skip_stakeholders_path(@record)
    assert_equal "s4_final", @record.reload.stage_key, "final approval has no skip"
    sign_out @ppm

    sign_in @legal_head
    patch dashboard_documenter_answer_approval_path(@record.stage_approvals.find_by(org_unit: @legal)), params: { decision: "approved" }
    assert_equal "s5_toPublish", @record.reload.stage_key
    sign_out @legal_head

    sign_in @ppm
    patch dashboard_documenter_publish_mode_path(@record), params: { mode: "assign" }
    post dashboard_documenter_assign_task_path(@record), params: { user_id: @contributor.id }
    post dashboard_documenter_publish_path(@record)
    assert_equal "s5_toPublish", @record.reload.stage_key, "cannot confirm while the publisher still holds it"
    sign_out @ppm

    sign_in @contributor
    post dashboard_documenter_submit_publication_path(@record), params: { link: "" }
    assert @record.stage_tasks.open.exists?
    post dashboard_documenter_submit_publication_path(@record), params: { link: "https://intranet.example/policies/data" }
    refute @record.stage_tasks.open.exists?
    sign_out @contributor

    sign_in @ppm
    post dashboard_documenter_publish_path(@record)
    @record.reload
    assert_equal "s5_published", @record.stage_key
    assert @record.published_at.present?
    assert_equal "https://intranet.example/policies/data", @record.published_link
    assert Notification.where(kind: "record_published").count >= 6, "everyone in the company is told"
    refute @record.editable?
  end

  test "publishing in the system only needs no publisher and files the PDF when Chromium is present" do
    @record.update!(current_stage: "s5_toPublish")
    sign_in @ppm
    patch dashboard_documenter_publish_mode_path(@record), params: { mode: "system" }
    post dashboard_documenter_publish_path(@record)
    @record.reload
    assert_equal "s5_published", @record.stage_key
    if RecordPdfRenderer.available?
      assert @record.published_pdf_upload.present?
      assert_equal Folder.find_by(org_unit_id: @unit.id), @record.published_pdf_upload.folder
    end
  end

  # ---- Procedure design -------------------------------------------------------

  test "a procedure is drawn from its steps and the drawing reviewed before final approval" do
    procedure = @company.pp_records.create!(record_type: "procedure", title_en: "Pay a supplier",
      owner_org_unit: @unit, pp_process: level_two_process(@company), current_stage: "s2_prep")

    sign_in @head
    post dashboard_pp_record_record_steps_path(procedure), params: { pp_process_step: { activity: "Receive invoice", responsible_title: "Clerk" } }
    post dashboard_pp_record_record_steps_path(procedure), params: { pp_process_step: { activity: "Approve payment", responsible_title: "Manager", duration_value: 1, duration_unit: "days" } }
    assert_equal [ 1, 2 ], procedure.steps.pluck(:position)
    sign_out @head

    procedure.update!(current_stage: "s3_design")
    sign_in @ppm
    post dashboard_documenter_design_path(procedure)
    diagram = procedure.diagrams.first
    assert_redirected_to dashboard_pp_diagram_path(diagram)
    assert_equal 2, diagram.elements.where.not(pp_process_step_id: nil).count

    # Editing the drawing edits the step, and back.
    element = diagram.elements.find_by(pp_process_step_id: procedure.steps.first.id)
    element.update!(title: "Receive and log invoice")
    assert_equal "Receive and log invoice", procedure.steps.first.reload.activity
    procedure.steps.last.update!(activity: "Approve and pay")
    assert_equal "Approve and pay", diagram.elements.find_by(pp_process_step_id: procedure.steps.last.id).reload.title

    post dashboard_documenter_advance_record_path(procedure)
    assert_equal "s3_designReview", procedure.reload.stage_key
    post dashboard_documenter_advance_record_path(procedure)
    assert_equal "s4_final", procedure.reload.stage_key
  end

  # ---- Glossary ---------------------------------------------------------------

  test "a glossary term is approved by the P&P Manager and becomes a company term" do
    term = @company.pp_records.create!(record_type: "glossary", title_en: "CAPA", description: "Corrective and preventive action")
    assert_equal "g1_submitted", term.stage_key

    sign_in @contributor
    post dashboard_documenter_publish_path(term)
    assert_equal "g1_submitted", term.reload.stage_key

    sign_out @contributor
    sign_in @ppm
    post dashboard_documenter_publish_path(term)
    assert_equal "g2_published", term.reload.stage_key
    assert @company.glossary_terms.exists?(term_en: "CAPA")
  end

  # ---- Settings (unchanged) ---------------------------------------------------

  test "settings renders every stage target and the working week" do
    sign_in @admin
    get dashboard_general_settings_documenter_path
    assert_response :success
    PpStage::KEYS.each { |key| assert_select "input[name=?]", "targets[#{key}]" }
    assert_select "input[name='weekend_days[]']"
  end

  test "saving settings stores targets and the weekend" do
    sign_in @admin
    patch dashboard_update_documenter_settings_path, params: { targets: { "s2_prep" => "14", "s4_final" => "7" }, weekend_days: [ "0", "6" ] }
    assert_equal 14, PpStageTarget.days_for(@company.reload, "s2_prep")
    assert_equal 7, PpStageTarget.days_for(@company, "s4_final")
    assert_equal [ 0, 6 ], @company.reload.weekend_days
  end

  test "holidays can be added and removed" do
    sign_in @admin
    assert_difference -> { @company.company_holidays.count }, 1 do
      post dashboard_documenter_holidays_path, params: { name: "Eid", start_date: "2026-04-01", end_date: "2026-04-05" }
    end
    holiday = @company.company_holidays.last
    assert_difference -> { @company.company_holidays.count }, -1 do
      delete dashboard_documenter_holiday_path(holiday_id: holiday.id)
    end
  end

  test "a contributor cannot open Documenter settings" do
    sign_in @contributor
    get dashboard_general_settings_documenter_path
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

  # ---- P&P Manager flag -------------------------------------------------------

  test "the company admin names a quality manager as P&P Manager; a contributor cannot be one" do
    qm = create_user("doc-qm", CompanyUser::ROLES[:company_quality_manager])
    sign_in @admin
    patch dashboard_toggle_pp_manager_path(qm)
    assert qm.company_user.reload.pp_manager?
    patch dashboard_toggle_pp_manager_path(@contributor)
    refute @contributor.company_user.reload.pp_manager
  end
end
