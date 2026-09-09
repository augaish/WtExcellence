# Shared setup for what is written inside a record during the Documenter's
# content stages: clauses, comments, steps. The record lookup and the "may this
# person write here" rule live once, here.
class Dashboard::DocumenterContentController < Dashboard::BaseController
  requires_module :pp
  before_action :authenticate_user!
  before_action :set_record
  before_action :ensure_can_edit_content

  private

  def company
    @company ||= current_company
  end

  def set_record
    @record = company&.pp_records&.find_by(id: params[:pp_record_id])
    return if @record

    redirect_to dashboard_documenter_path, alert: t("pp_records.flash.not_found"), status: :see_other
  end

  def actions
    @actions ||= DocumenterActions.new(record: @record, user: current_user, company: company)
  end

  def manager?
    PpStageTransitionService.manager?(current_user, company)
  end

  def can_edit_content?
    return false if @record.published?
    return true if manager?

    stage = @record.stage_key
    holder = @record.stage_tasks.for_stage(stage).open.for_user(current_user).exists?
    (PpStage.content_stage?(stage) || stage == "s3_design") && (holder || actions.unit_head?)
  end

  def can_comment?
    return false if @record.published?
    return true if manager?

    @record.stage_tasks.for_stage(@record.stage_key).open.for_user(current_user).exists? ||
      @record.stage_approvals.for_stage(@record.stage_key).joins(:org_unit).where(org_units: { head_user_id: current_user.id }).exists?
  end

  def ensure_can_edit_content
    return if can_edit_content?

    back(alert: t("documenter.flash.no_permission"))
  end

  def back(notice: nil, alert: nil)
    redirect_to dashboard_documenter_record_path(@record), notice: notice, alert: alert, status: :see_other
  end
end
