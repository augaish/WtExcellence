# The Documenter: every record's journey through its flow, and the worklist of
# what needs the signed-in person's hand right now.
#
# Moving between stages is PpStageTransitionService; what people do inside a
# stage (hand out work, answer for a unit, ask for approvals, publish) is
# DocumenterActions. This controller only reads requests and reports back.
class Dashboard::DocumenterController < Dashboard::BaseController
  requires_module :pp
  before_action :authenticate_user!
  before_action :ensure_company_present
  before_action :ensure_can_manage, only: [ :settings, :update_settings, :create_holiday, :destroy_holiday, :return_to ]
  before_action :set_record, only: [
    :show, :advance_one, :assign_task, :submit_task, :request_approvals, :resend_approvals,
    :skip_stakeholders, :publish_mode, :submit_publication, :publish, :design
  ]

  helper_method :can_manage_documenter?, :manager?, :stage_target_for, :working_days_for

  # The worklist: what needs me, then (for managers) everything by phase.
  def index
    @inbox = DocumenterInbox.new(user: current_user, company: company)
    @phase = params[:phase].presence
    @phase = PpStage::PHASES.first unless PpStage::PHASES.include?(@phase)

    return unless manager?

    records = company.pp_records.active.latest.where.not(record_type: PpRecord::DOA_TYPES)
      .includes(:owner_org_unit, :owner_user, :stage_tasks, :stage_approvals).to_a
    @by_stage = records.group_by(&:stage_key)
    @counts_by_phase = PpStage::PHASES.index_with do |phase|
      PpStage.in_phase(phase).sum { |d| (@by_stage[d[:key]] || []).size }
    end
    @stages = PpStage.in_phase(@phase)
  end

  # One record's journey: the route, and the panel for where it stands.
  def show
    @actions = DocumenterActions.new(record: @record, user: current_user, company: company)
    @approvals = @record.stage_approvals.for_stage(@record.stage_key).includes(org_unit: :head_user).ordered.to_a
    @my_approval = @approvals.find { |a| @actions.can_answer?(a) }
    @task = @record.current_task
    @my_task = @record.stage_tasks.for_stage(@record.stage_key).open.for_user(current_user).first
    @eligible = @actions.eligible_assignees.to_a
    @org_units = company.org_units.active.ordered.includes(:head_user).to_a
    @clauses = @record.clauses.main.includes(:children, comments: :user).to_a
    @steps = @record.steps.includes(:responsible_org_unit).to_a
    @diagram = @record.diagrams.first
    @can_edit_content = can_edit_content?
    @can_comment = can_comment?
  end

  # ---- Moving ------------------------------------------------------------

  def advance_one
    PpStageTransitionService.advance(record: @record, user: current_user, company: company)
    back_to_record(notice: t("documenter.flash.advanced", count: 1))
  rescue PpStageTransitionService::TransitionError => e
    back_to_record(alert: e.message)
  end

  # "Move selected forward" from the worklist — every record validated independently.
  def advance
    records = company.pp_records.where(id: Array(params[:record_ids]).reject(&:blank?)).to_a
    return redirect_back_to_worklist(alert: t("documenter.flash.nothing_selected")) if records.empty?

    result = PpStageTransitionService.advance_many(records: records, user: current_user, company: company)
    if result.success?
      redirect_back_to_worklist(notice: t("documenter.flash.advanced", count: result.moved.size))
    else
      detail = result.errors.first(3).map { |e| "#{e[:record].display_title}: #{e[:message]}" }.join(" · ")
      redirect_back_to_worklist(alert: t("documenter.flash.advanced_partial", moved: result.moved.size, skipped: result.skipped.size, detail: detail))
    end
  end

  # Return a record to an earlier stage, always with a reason.
  def return_to
    record = company.pp_records.find_by(id: params[:record_id] || params[:id])
    return redirect_back_to_worklist(alert: t("pp_records.flash.not_found")) unless record

    PpStageTransitionService.return_to(record: record, user: current_user, company: company,
      stage_key: params[:stage_key], reason: params[:reason])
    redirect_to dashboard_documenter_record_path(record), notice: t("documenter.flash.returned", title: record.display_title), status: :see_other
  rescue PpStageTransitionService::TransitionError => e
    redirect_to dashboard_documenter_record_path(record), alert: e.message, status: :see_other
  end

  # ---- Inside a stage ----------------------------------------------------

  def assign_task
    assignee = company.users.find_by(id: params[:user_id])
    return back_to_record(alert: t("documenter.flash.user_not_found")) unless assignee

    actions.assign_task(assignee, note: params[:note])
    back_to_record(notice: t("documenter.flash.task_assigned", name: assignee.name))
  rescue DocumenterActions::NotPermitted, DocumenterActions::Invalid => e
    back_to_record(alert: e.message)
  end

  def submit_task
    task = actions.submit_task(note: params[:note])
    back_to_record(notice: t("documenter.flash.task_submitted", name: task.assigned_by&.name.to_s))
  rescue DocumenterActions::NotPermitted, DocumenterActions::Invalid => e
    back_to_record(alert: e.message)
  end

  # Units to ask, grouped: params[:groups] = { "1" => [unit ids], "2" => [...] }.
  # A flat params[:org_unit_ids] is group 1 (everyone at once).
  def request_approvals
    groups = params.fetch(:groups, {}).permit!.to_h
    groups = { "1" => Array(params[:org_unit_ids]) } if groups.empty?
    actions.request_approvals(groups, auto_days: params[:auto_approve_days].presence)
    back_to_record(notice: t("documenter.flash.approvals_requested"))
  rescue DocumenterActions::NotPermitted, DocumenterActions::Invalid, ActiveRecord::RecordInvalid => e
    back_to_record(alert: e.message)
  end

  def answer_approval
    approval = find_approval or return
    record = approval.pp_record
    DocumenterActions.new(record: record, user: current_user, company: company)
      .answer_approval(approval, params[:decision], comment: params[:comment])
    redirect_to dashboard_documenter_record_path(record), notice: t("documenter.flash.answered", unit: approval.org_unit.display_name), status: :see_other
  rescue DocumenterActions::NotPermitted, DocumenterActions::Invalid, ActiveRecord::RecordInvalid => e
    redirect_to dashboard_documenter_record_path(record), alert: e.message, status: :see_other
  end

  def resend_approvals
    actions.resend_approvals(scope: params[:scope] == "all" ? "all" : "rejected")
    back_to_record(notice: t("documenter.flash.resent"))
  rescue DocumenterActions::NotPermitted => e
    back_to_record(alert: e.message)
  end

  def remove_approval
    approval = find_approval or return
    record = approval.pp_record
    unit_name = approval.org_unit.display_name
    DocumenterActions.new(record: record, user: current_user, company: company).remove_approval(approval)
    redirect_to dashboard_documenter_record_path(record), notice: t("documenter.flash.approval_removed", unit: unit_name), status: :see_other
  rescue DocumenterActions::NotPermitted => e
    redirect_to dashboard_documenter_record_path(record), alert: e.message, status: :see_other
  end

  def skip_stakeholders
    PpStageTransitionService.advance(record: @record, user: current_user, company: company, skip_stakeholders: true)
    back_to_record(notice: t("documenter.flash.skipped_stakeholders"))
  rescue PpStageTransitionService::TransitionError => e
    back_to_record(alert: e.message)
  end

  # ---- Design ------------------------------------------------------------

  # Draws the procedure from its steps and opens the drawing.
  def design
    return back_to_record(alert: t("documenter.flash.no_permission")) unless can_edit_content?
    return back_to_record(alert: t("architect.sync.no_steps")) if @record.steps.none?

    diagram = @record.diagrams.first || company.pp_diagrams.create!(owner: @record, name: @record.display_title)
    DiagramStepSync.generate(diagram, @record)
    redirect_to dashboard_pp_diagram_path(diagram), status: :see_other
  end

  # ---- Publishing --------------------------------------------------------

  def publish_mode
    actions.choose_publish_mode(params[:mode].to_s)
    back_to_record(notice: t("documenter.flash.publish_mode_saved"))
  rescue DocumenterActions::NotPermitted, DocumenterActions::Invalid => e
    back_to_record(alert: e.message)
  end

  def submit_publication
    actions.submit_publication(params[:link])
    back_to_record(notice: t("documenter.flash.publication_submitted"))
  rescue DocumenterActions::NotPermitted, DocumenterActions::Invalid, ActiveRecord::RecordInvalid => e
    back_to_record(alert: e.message)
  end

  # The P&P Manager confirms, or publishes in the system only; a glossary term
  # is approved the same way.
  def publish
    return back_to_record(alert: t("documenter.flash.no_permission")) unless manager?
    return back_to_record(alert: t("documenter.errors.work_outstanding")) if @record.stage_tasks.for_stage(@record.stage_key).open.exists?

    RecordPublisher.publish!(@record, by: current_user, company: company)
    back_to_record(notice: t("documenter.flash.published", title: @record.display_title))
  rescue PpStageTransitionService::TransitionError, ActiveRecord::RecordInvalid => e
    back_to_record(alert: e.message)
  end

  # ---- Settings ----------------------------------------------------------

  def settings
    @targets = PpStage::KEYS.index_with { |key| stage_target_for(key) }
    @holidays = company.company_holidays.ordered.to_a
    @weekend_days = WorkingDaysService.new(company).weekend_days
  end

  def update_settings
    submitted = params.fetch(:targets, {}).permit!.to_h

    ActiveRecord::Base.transaction do
      submitted.each do |stage_key, value|
        next unless PpStage.exists?(stage_key)

        target = company.pp_stage_targets.find_or_initialize_by(stage_key: stage_key)
        target.target_days = value.to_i
        target.save!
      end

      if params[:weekend_days].present?
        days = Array(params[:weekend_days]).reject(&:blank?).map(&:to_i).select { |d| d.between?(0, 6) }
        company.update!(weekend_days: days)
      end
    end

    redirect_to dashboard_general_settings_documenter_path, notice: t("documenter.flash.settings_saved"), status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    redirect_to dashboard_general_settings_documenter_path, alert: e.record.errors.full_messages.to_sentence, status: :see_other
  end

  def create_holiday
    holiday = company.company_holidays.new(name: params[:name], start_date: params[:start_date], end_date: params[:end_date])
    if holiday.save
      redirect_to dashboard_general_settings_documenter_path, notice: t("documenter.flash.holiday_added"), status: :see_other
    else
      redirect_to dashboard_general_settings_documenter_path, alert: holiday.errors.full_messages.to_sentence, status: :see_other
    end
  end

  def destroy_holiday
    company.company_holidays.find_by(id: params[:holiday_id])&.destroy
    redirect_to dashboard_general_settings_documenter_path, notice: t("documenter.flash.holiday_removed"), status: :see_other
  end

  private

  def company
    @company ||= current_company
  end

  def ensure_company_present
    return if company

    redirect_to dashboard_overview_path, alert: t("pp_records.flash.no_company"), status: :see_other
  end

  def manager?
    PpStageTransitionService.manager?(current_user, company)
  end
  alias can_manage_documenter? manager?

  def ensure_can_manage
    return if manager?

    redirect_to dashboard_documenter_path, alert: t("documenter.flash.no_permission"), status: :see_other
  end

  def set_record
    @record = company.pp_records.find_by(id: params[:id])
    return if @record

    redirect_to dashboard_documenter_path, alert: t("pp_records.flash.not_found"), status: :see_other
  end

  def actions
    @actions ||= DocumenterActions.new(record: @record, user: current_user, company: company)
  end

  def find_approval
    approval = PpStageApproval.joins(:pp_record).where(pp_records: { company_id: company.id }).find_by(id: params[:approval_id])
    return approval if approval

    redirect_back_to_worklist(alert: t("documenter.flash.approval_not_found"))
    nil
  end

  # Clauses and steps are written by whoever holds the work in the content
  # stages: the person with the open task, the unit head, or a manager.
  def can_edit_content?
    return false if @record.published?
    return true if manager?

    stage = @record.stage_key
    holder = @record.stage_tasks.for_stage(stage).open.for_user(current_user).exists?
    (PpStage.content_stage?(stage) || stage == "s3_design") && (holder || actions.unit_head?)
  end

  # Comments are left during review: by managers, their team member holding the
  # task, and by the unit heads asked to approve.
  def can_comment?
    return false if @record.published?
    return true if manager?

    @record.stage_tasks.for_stage(@record.stage_key).open.for_user(current_user).exists? ||
      @record.stage_approvals.for_stage(@record.stage_key).joins(:org_unit).where(org_units: { head_user_id: current_user.id }).exists?
  end

  def stage_target_for(stage_key)
    PpStageTarget.days_for(company, stage_key)
  end

  def working_days_for(record)
    record.working_days_in_stage
  end

  def back_to_record(notice: nil, alert: nil)
    redirect_to dashboard_documenter_record_path(@record), notice: notice, alert: alert, status: :see_other
  end

  def redirect_back_to_worklist(**flash_opts)
    redirect_to dashboard_documenter_path(phase: params[:phase]), status: :see_other, **flash_opts
  end
end
