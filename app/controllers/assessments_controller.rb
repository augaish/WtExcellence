class AssessmentsController < Dashboard::BaseController
  before_action :block_platform_admins
  before_action :set_clause
  before_action :set_tool_context
  before_action :set_assessment_data
  before_action :set_user_role

  def show
    @readonly = viewer? || status_prevents_editing?
    @sibling_clauses = sibling_terminal_clauses
    @overall_score = compute_current_score
    @assessment_auditor = @assessment&.auditor_user
  end

  def autosave
    return render(json: { error: "Readonly" }, status: :forbidden) if viewer?

    checklist_item_id = params[:checklist_item_id]
    tool_checkpoint_id = params[:tool_checkpoint_id]
    summary = params[:summary]

    unless checklist_item_id.present? && tool_checkpoint_id.present? && @tool_clause
      return render(json: { error: "Missing params" }, status: :unprocessable_entity)
    end

    # Validate IDs belong to this clause/tool
    valid_item_ids = @checklist_items.map { |i| i.id.to_s }.to_set
    valid_cp_ids = @checkpoints.map { |cp| cp.id.to_s }.to_set
    unless valid_item_ids.include?(checklist_item_id.to_s) && valid_cp_ids.include?(tool_checkpoint_id.to_s)
      return render(json: { error: "Invalid params" }, status: :forbidden)
    end

    # Contributors can only autosave checkpoints they're assigned to
    if @is_contributor && !@is_admin_or_qm && !@is_auditor
      item_index = @checklist_items.index { |i| i.id.to_s == checklist_item_id.to_s }
      unless item_index && user_can_edit_checkpoint?(item_index)
        return render(json: { error: "Not assigned" }, status: :forbidden)
      end
    end

    cs = CheckpointSummary.find_or_create_by!(
      tool_clause_id: @tool_clause.id,
      checklist_item_id: checklist_item_id,
      tool_checkpoint_id: tool_checkpoint_id,
      company_id: current_company.id
    )
    cs.update!(summary: summary.to_s.truncate(100), last_edited_by_user_id: current_user.id)

    render json: { success: true }
  end

  def add_comment
    unless @is_auditor || @is_admin_or_qm
      render json: { error: "Not authorized" }, status: :forbidden
      return
    end

    feedback = params[:feedback]&.strip
    if feedback.blank?
      render json: { error: "Comment cannot be blank" }, status: :unprocessable_entity
      return
    end

    unless @assessment
      render json: { error: "No assessment found" }, status: :not_found
      return
    end

    evaluation = AssignmentEvaluation.create!(
      assessment_id: @assessment.id,
      evaluator_id: current_user.id,
      evaluation_status: "auditor_reviewed",
      feedback: feedback.truncate(300)
    )

    log_assessment_action("ASSESSMENT_COMMENT", "auditor_reviewed", feedback: feedback.truncate(300))

    initials = current_user.name&.split(" ")&.map(&:first)&.join("")&.upcase&.slice(0, 2) || "?"
    comment_html = render_to_string(partial: "assessments/comment_item", locals: { evaluation: evaluation, initials: initials }, layout: false, formats: [:html])

    render json: { success: true, html: comment_html }
  end

  def assign_auditor
    return if prevent_viewer_action
    unless @is_admin_or_qm
      respond_to do |format|
        format.html { redirect_back(fallback_location: clause_assessment_path(@clause), alert: t("assessments.no_access")) }
        format.json { render json: { error: "Not authorized" }, status: :forbidden }
      end
      return
    end

    auditor_id = params[:auditor_id]
    auditor = auditor_id.present? ? User.find_by(id: auditor_id) : nil

    if auditor_id.present? && auditor.nil?
      respond_to do |format|
        format.html { redirect_back(fallback_location: clause_assessment_path(@clause), alert: t("assessments.auditor_not_found")) }
        format.json { render json: { error: "Auditor not found" }, status: :not_found }
      end
      return
    end

    if auditor && @assessment&.assessment_users&.where(user_id: auditor.id, role: "contributor")&.exists?
      respond_to do |format|
        format.html { redirect_back(fallback_location: clause_assessment_path(@clause), alert: t("assessments.cannot_be_auditor_and_contributor")) }
        format.json { render json: { error: t("assessments.cannot_be_auditor_and_contributor") }, status: :unprocessable_entity }
      end
      return
    end

    ActiveRecord::Base.transaction do
      ensure_assessment!

      # Remove existing auditor
      @assessment.assessment_users.where(role: "auditor").destroy_all

      # Assign the new auditor
      if auditor
        @assessment.assessment_users.find_or_create_by!(user_id: auditor.id, role: "auditor") do |au|
          au.assigner_user_id = current_user.id
        end

        AuditLogService.log_action(
          actor_user: current_user,
          company: current_company,
          action: "ASSIGN_AUDITOR_TO_ASSESSMENT",
          entity_type: "assessment",
          entity_id: @assessment.id,
          payload: {
            clause_id: @clause.id,
            clause_code: @clause.code,
            auditor_id: auditor.id,
            auditor_name: auditor.name
          }
        )
      end
    end

    respond_to do |format|
      format.html { redirect_to clause_assessment_path(@clause), notice: t("assessments.auditor_assigned") }
      format.json { render json: { success: true } }
    end
  end

  def update
    return if prevent_viewer_action

    commit = params.dig(:assessment, :commit)

    if commit == "reopen"
      feedback_text = params.dig(:assessment, :feedback).to_s.strip
      if feedback_text.blank?
        redirect_to clause_assessment_path(@clause), alert: t("assessments.reevaluate_reason_required") and return
      end
    end

    ActiveRecord::Base.transaction do
      ensure_assessment!

      case commit
      when "approve"
        approve_assessment
        save_feedback("approved")
      when "reject"
        reject_assessment
        save_feedback("rejected")
      when "reopen"
        reopen_assessment
        save_feedback("reopened")
      when "submit_for_review"
        persist_scores if @is_auditor || @is_admin_or_qm
        persist_checkpoint_summaries
        submit_for_review
      else
        persist_scores if @is_auditor || @is_admin_or_qm
        persist_checkpoint_summaries
        save_draft(collect_summary_snapshot)
      end
    end

    ClauseScorePropagator.propagate_from_terminal_clause(@clause, current_company)
    redirect_to clause_assessment_path(@clause), notice: t("assessments.saved")
  rescue ActiveRecord::RecordInvalid => e
    flash.now[:alert] = e.message
    set_assessment_data
    @readonly = false
    @sibling_clauses = sibling_terminal_clauses
    @overall_score = compute_current_score
    @assessment_auditor = @assessment&.auditor_user
    render :show, status: :unprocessable_entity
  end

  private

  # ---- Role detection ----

  def set_user_role
    cu = current_user&.company_user

    @is_admin_or_qm = cu&.company_admin? || cu&.company_quality_manager?

    @is_auditor = cu&.company_auditor?
    @is_viewer = cu&.company_viewer?

    # Contributor: a user assigned to at least one checklist item for this assessment
    @assigned_checklist_item_ids = if @assessment
      @assessment.assessment_users
        .where(user_id: current_user.id, role: "contributor")
        .where.not(checklist_item_id: nil)
        .pluck(:checklist_item_id)
        .to_set
    else
      Set.new
    end

    @is_contributor = @assigned_checklist_item_ids.any?

    @can_see_scoring = @is_auditor || @is_admin_or_qm
    @can_manage_assignments = @is_admin_or_qm
    @can_approve = @is_admin_or_qm
  end
  helper_method :clause_status

  # ---- Per-checkpoint mapping ----

  def user_can_edit_checkpoint?(checklist_item_index)
    return true if @is_admin_or_qm || @is_auditor
    return false if @is_viewer || !@is_contributor

    item = @checklist_items[checklist_item_index]
    item && @assigned_checklist_item_ids.include?(item.id)
  end
  helper_method :user_can_edit_checkpoint?

  # ---- Data loading ----

  def set_clause
    @clause = Clause.includes(:clause_translations, :checklist_items).find(params[:clause_id])
    @standard = @clause.standard_version&.standard

    unless @clause.leaf?
      redirect_to standard_path(@standard), alert: t("assessments.not_terminal")
      return
    end

    unless current_company && @standard &&
           CompanyStandard.exists?(company_id: current_company.id, standard_id: @standard.id)
      redirect_back(fallback_location: root_path, alert: t("assessments.no_access"))
    end
  end

  def set_tool_context
    return unless @clause

    @tool_clause = @clause.tool_clause
    @tool = @tool_clause&.tool

    if @tool
      @checkpoints = @tool.checkpoints
                         .includes(subcheckpoints: :tool_subcheckpoint_translations)
                         .order(:display_order)
      @subcheckpoints = @checkpoints.flat_map { |cp| cp.subcheckpoints.sort_by { |s| s.display_order || 0 } }
    else
      @checkpoints = []
      @subcheckpoints = []
    end
  end

  def set_assessment_data
    return unless @clause

    @checklist_items = @clause.checklist_items
                              .includes(:checklist_item_translations)
                              .order(:sort_order)

    # Load or create the single assessment for this clause + company
    @assessment = load_assessment
    @assessment_scores = load_assessment_scores
    @checkpoint_summaries = load_checkpoint_summaries
    @company_users = current_company&.users || []
    @folders_for_upload = current_company ? Folder.where(company_id: current_company.id).where.not(company_id: nil).order(:name) : Folder.none

    # Load comments and activity log
    if @assessment&.persisted?
      @evaluations_with_comments = @assessment.assignment_evaluations
        .where.not(feedback: [ nil, "" ])
        .includes(:evaluator)
        .order(created_at: :desc)

      @audit_logs = AuditLog
        .where(entity_type: "assessment", entity_id: @assessment.id)
        .or(
          AuditLog.where(entity_type: "assessment")
                  .where("payload_json->>'tool_clause_id' = ?", @tool_clause&.id.to_s)
                  .where(action: %w[
                    ASSIGN_USER_TO_TOOL_SUBCHECKPOINT
                    ASSIGN_AUDITOR_TO_ASSESSMENT
                    UNASSIGN_USER_FROM_TOOL_SUBCHECKPOINT
                  ])
        )
        .includes(:actor_user)
        .order(created_at: :desc)
        .limit(50)
    else
      @evaluations_with_comments = AssignmentEvaluation.none
      @audit_logs = AuditLog.none
    end
  end

  def load_assessment
    return nil unless @tool_clause && current_company

    Assessment.find_or_create_by!(
      tool_clause_id: @tool_clause.id,
      company_id: current_company.id
    )
  end

  def load_assessment_scores
    return {} unless @assessment

    @assessment.assessment_scores.index_by(&:tool_subcheckpoint_id)
  end

  def load_checkpoint_summaries
    return {} unless @tool_clause && current_company

    CheckpointSummary
      .where(tool_clause_id: @tool_clause.id, company_id: current_company.id)
      .each_with_object({}) do |cs, hash|
        hash[cs.checklist_item_id] ||= {}
        hash[cs.checklist_item_id][cs.tool_checkpoint_id] = cs
      end
  end

  # ---- Persistence ----

  def persist_scores
    return unless params.dig(:assessment, :scores) && @assessment

    subs_by_id = @subcheckpoints.index_by { |s| s.id.to_s }

    params[:assessment][:scores].each do |subcheckpoint_id, value|
      next unless valid_subcheckpoint_id?(subcheckpoint_id)

      sub = subs_by_id[subcheckpoint_id.to_s]
      next unless sub

      score_record = AssessmentScore.find_or_create_by!(
        assessment_id: @assessment.id,
        tool_subcheckpoint_id: subcheckpoint_id
      )

      case sub.scoring_type
      when "Number"
        min = sub.min_score&.to_f || 0.0
        max = sub.max_score&.to_f || 100.0
        clamped = value.to_f.clamp(min, max)
        score_record.update!(score: clamped, percentage_score: nil)
      when "Multiple Choice"
        score_record.update!(percentage_score: value.to_f.clamp(0, 100))
      else
        score_record.update!(percentage_score: value.to_f.clamp(0, 100))
      end
    end
  end

  def persist_checkpoint_summaries
    return unless params.dig(:assessment, :checkpoint_summaries) && @tool_clause
    return if @is_viewer

    valid_item_ids = @checklist_items.map { |i| i.id.to_s }.to_set
    valid_cp_ids = @checkpoints.map { |cp| cp.id.to_s }.to_set

    params[:assessment][:checkpoint_summaries].each do |checklist_item_id, checkpoints_hash|
      next unless valid_item_ids.include?(checklist_item_id.to_s)

      checkpoints_hash.each do |checkpoint_id, value|
        next unless valid_cp_ids.include?(checkpoint_id.to_s)

        cs = CheckpointSummary.find_or_create_by!(
          tool_clause_id: @tool_clause.id,
          checklist_item_id: checklist_item_id,
          tool_checkpoint_id: checkpoint_id,
          company_id: current_company.id
        )
        cs.update!(summary: value.to_s.truncate(100), last_edited_by_user_id: current_user.id)
      end
    end
  end

  def valid_subcheckpoint_id?(subcheckpoint_id)
    @allowed_subcheckpoint_ids ||= @subcheckpoints.map { |s| s.id.to_s }.to_set
    @allowed_subcheckpoint_ids.include?(subcheckpoint_id.to_s)
  end

  # ---- Status transitions ----

  def ensure_assessment!
    @assessment ||= Assessment.find_or_create_by!(
      tool_clause_id: @tool_clause.id,
      company_id: current_company.id
    )
  end

  def save_draft(summaries = {})
    return unless @assessment
    @assessment.update!(status: "in_drafts") if @assessment.status == "not_started"
    log_assessment_action("ASSESSMENT_SAVE_DRAFT", @assessment.status, summaries: summaries) if summaries.any?
  end

  def submit_for_review
    return unless @assessment
    return unless %w[not_started in_drafts needs_changes].include?(@assessment.status)

    @assessment.update!(status: "under_review")
    log_assessment_action("ASSESSMENT_SUBMIT_FOR_REVIEW", "under_review")
  end

  def approve_assessment
    return unless @can_approve && @assessment
    return unless @assessment.status == "under_review"

    @assessment.update!(status: "approved")
    log_assessment_action("ASSESSMENT_APPROVED", "approved")
  end

  def reject_assessment
    return unless @can_approve && @assessment
    return unless @assessment.status == "under_review"

    @assessment.update!(status: "needs_changes")
    log_assessment_action("ASSESSMENT_REJECTED", "needs_changes")
  end

  def reopen_assessment
    return unless @is_admin_or_qm && @assessment
    return unless @assessment.status == "approved"

    @assessment.update!(status: "needs_changes")
    log_assessment_action("ASSESSMENT_REOPENED", "needs_changes")
  end

  def save_feedback(evaluation_status)
    feedback = params.dig(:assessment, :feedback)&.strip
    return if feedback.blank?
    return unless @is_auditor || @is_admin_or_qm
    return unless @assessment

    AssignmentEvaluation.create!(
      assessment_id: @assessment.id,
      evaluator_id: current_user.id,
      evaluation_status: evaluation_status,
      feedback: feedback.truncate(300)
    )

    log_assessment_action("ASSESSMENT_COMMENT", evaluation_status, feedback: feedback.truncate(300))
  end

  def collect_summary_snapshot
    return {} unless params.dig(:assessment, :checkpoint_summaries)

    items_by_id = @checklist_items.index_by { |i| i.id.to_s }
    cps_by_id = @checkpoints.index_by { |cp| cp.id.to_s }
    snapshot = {}

    params[:assessment][:checkpoint_summaries].each do |item_id, cps_hash|
      item = items_by_id[item_id.to_s]
      next unless item

      label = item.code || "Checkpoint"
      cps_hash.each do |cp_id, value|
        cp = cps_by_id[cp_id.to_s]
        next unless cp
        next if value.blank?

        snapshot[label] ||= {}
        snapshot[label][cp.name] = value.to_s.truncate(60)
      end
    end

    snapshot
  end

  def log_assessment_action(action, status, extra_payload = {})
    AuditLogService.log_action(
      actor_user: current_user,
      company: current_company,
      action: action,
      entity_type: "assessment",
      entity_id: @assessment&.id,
      payload: {
        tool_clause_id: @tool_clause&.id,
        clause_id: @clause.id,
        clause_code: @clause.code,
        status: status
      }.merge(extra_payload)
    )
  end

  # ---- Helpers ----

  def compute_current_score
    return nil unless @tool_clause
    ClauseScoreCalculator.new(@tool_clause).calculate_score(current_company)
  end

  def sibling_terminal_clauses
    parent = @clause&.parent
    return [] unless parent
    parent.children.select(&:leaf?).sort_by(&:sort_order)
  end

  def status_prevents_editing?
    return false unless @assessment
    return true if @assessment.status == "approved"
    return true if @assessment.status == "under_review" && !@is_admin_or_qm
    false
  end

  def clause_status
    return "not_started" unless @assessment
    @assessment.status
  end

  def block_platform_admins
    return unless current_user&.platform_admin?
    redirect_back(fallback_location: dashboard_path, alert: t("assessments.no_access"))
  end
end
