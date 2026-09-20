# Review notes on one clause, and the act of resolving them.
class Dashboard::PpClauseCommentsController < Dashboard::DocumenterContentController
  skip_before_action :ensure_can_edit_content
  before_action :ensure_can_comment, only: [ :create ]

  def create
    clause = @record.clauses.find_by(id: params[:clause_id])
    return back(alert: t("pp_records.flash.not_found")) if clause.nil?

    comment = clause.comments.new(user: current_user, stage_key: @record.stage_key, body: params[:body])
    if comment.save
      # The people writing the record hear about the note: whoever holds a task here, and the owner.
      holders = @record.stage_tasks.for_stage(@record.stage_key).open.includes(:user).map(&:user)
      Notify.people(holders + [ @record.owner_user ], kind: "record_comment_added", source: @record,
        link_path: dashboard_documenter_record_path(@record), actor: current_user, title: @record.display_title, clause: clause.number)
      back(notice: t("documenter.flash.comment_added"))
    else
      back(alert: comment.errors.full_messages.to_sentence)
    end
  end

  def resolve
    comment = PpClauseComment.joins(clause: :pp_record).where(pp_records: { id: @record.id }).find_by(id: params[:id])
    return back(alert: t("pp_records.flash.not_found")) if comment.nil?
    return back(alert: t("documenter.flash.no_permission")) unless can_edit_content?

    comment.update!(resolved_at: Time.current)
    Notify.person(comment.user, kind: "record_comment_resolved", source: @record,
      link_path: dashboard_documenter_record_path(@record), actor: current_user, title: @record.display_title, clause: comment.clause.number)
    back(notice: t("documenter.flash.clause_saved"))
  end

  private

  def ensure_can_comment
    return if can_comment?

    back(alert: t("documenter.flash.no_permission"))
  end
end
