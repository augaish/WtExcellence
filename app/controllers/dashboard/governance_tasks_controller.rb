# The scoped task page: what one person was asked to do on a commitment or a
# risk's control, with the evidence and a submit-for-review action, and no
# governance register behind it. Open to whoever holds the assignment,
# whatever their licence; the register itself stays protected.
class Dashboard::GovernanceTasksController < Dashboard::BaseController
  before_action :authenticate_user!
  before_action :ensure_company_present

  def commitment
    @commitment = assigned_commitment or return
  end

  # The owner reports the obligation as delivered; the record moves to
  # fulfilled and waits for the customer's verdict, recorded by a manager.
  def submit_commitment
    @commitment = assigned_commitment or return
    note = params[:fulfillment_note].to_s.strip
    if note.blank?
      return redirect_to dashboard_commitment_task_path(@commitment), alert: t("governance_tasks.note_required"), status: :see_other
    end

    @commitment.assign_attributes(status: "fulfilled", fulfillment_note: note,
      delivered_on: (params[:delivered_on].presence || Date.current), acceptance_status: "pending")
    if @commitment.save
      GovernanceTaskNotifier.submitted(record: @commitment, actor: current_user)
      redirect_to dashboard_commitment_task_path(@commitment), notice: t("governance_tasks.commitment_submitted"), status: :see_other
    else
      redirect_to dashboard_commitment_task_path(@commitment), alert: @commitment.errors.full_messages.to_sentence, status: :see_other
    end
  end

  def control
    @risk = assigned_risk or return
  end

  # The control owner says what the control did; the risk owner assesses it.
  def submit_control
    @risk = assigned_risk or return
    note = params[:control_evidence_note].to_s.strip
    if note.blank?
      return redirect_to dashboard_control_task_path(@risk), alert: t("governance_tasks.note_required"), status: :see_other
    end

    @risk.update!(control_evidence_note: note, control_evidence_submitted_at: Time.current)
    GovernanceTaskNotifier.submitted(record: @risk, actor: current_user)
    redirect_to dashboard_control_task_path(@risk), notice: t("governance_tasks.control_submitted"), status: :see_other
  end

  private

  def membership
    current_user&.company_user
  end

  def ensure_company_present
    return if current_company && membership

    redirect_to dashboard_overview_path, alert: t("governance_tasks.not_yours"), status: :see_other
  end

  def assigned_commitment
    commitment = CustomerCommitment.active.find_by(id: params[:id], company_id: current_company.id, owner_id: membership.id)
    return commitment if commitment

    redirect_to dashboard_overview_path, alert: t("governance_tasks.not_yours"), status: :see_other
    nil
  end

  def assigned_risk
    risk = Risk.active.find_by(id: params[:id], company_id: current_company.id, control_owner_id: membership.id)
    return risk if risk

    redirect_to dashboard_overview_path, alert: t("governance_tasks.not_yours"), status: :see_other
    nil
  end
end
