# Moves records through the lifecycle, and is the single place the rules are
# enforced. The client never picks a destination: it asks to go forward, or to
# return to a named earlier stage with a reason. Everything else is derived.
#
# Guarantees:
#   * forward goes to exactly ONE computed stage (branching on record type and
#     the intersections answer) — a crafted request cannot skip ahead
#   * backward is allowed only to an earlier stage ON THIS RECORD'S ROUTE, only
#     for permitted users, and always with a reason
#   * an approval-chain stage cannot be left until every unit has responded
#   * every move writes a transition row and stamps stage_entered_at, which is
#     what the duration/lateness maths reads
class PpStageTransitionService
  class TransitionError < StandardError; end
  class NotPermitted < TransitionError; end
  class InvalidTransition < TransitionError; end
  class ApprovalsPending < TransitionError; end

  Result = Struct.new(:moved, :skipped, :errors, keyword_init: true) do
    def success? = errors.empty?
  end

  def self.advance(record:, user:, company:)
    new(record: record, user: user, company: company).advance
  end

  def self.return_to(record:, user:, company:, stage_key:, reason:)
    new(record: record, user: user, company: company).return_to(stage_key, reason)
  end

  # Bulk "move selected forward" from the worklist. Each record is validated on
  # its own; one failure never blocks the rest.
  def self.advance_many(records:, user:, company:)
    moved = []
    skipped = []
    errors = []

    records.each do |record|
      new(record: record, user: user, company: company).advance
      moved << record
    rescue TransitionError => e
      skipped << record
      errors << { record: record, message: e.message }
    end

    Result.new(moved: moved, skipped: skipped, errors: errors)
  end

  def initialize(record:, user:, company:)
    @record = record
    @user = user
    @company = company
  end

  def advance
    ensure_can_move_forward!

    from = @record.stage_key
    to = @record.next_stage_key
    raise InvalidTransition, I18n.t("documenter.errors.no_next_stage") if to.blank?

    # An approval-chain stage is only complete when every unit has responded.
    if PpStage.approval_stage?(from) && !@record.approvals_complete?(from)
      raise ApprovalsPending, I18n.t("documenter.errors.approvals_pending")
    end

    apply!(from: from, to: to, direction: "forward", reason: nil)
  end

  def return_to(target_stage, reason)
    ensure_can_move_backward!

    if reason.to_s.strip.blank?
      raise InvalidTransition, I18n.t("documenter.errors.reason_required")
    end

    from = @record.stage_key
    unless PpStage.backward?(from, target_stage,
                             record_type: @record.record_type,
                             has_intersections: @record.has_intersections?)
      raise InvalidTransition, I18n.t("documenter.errors.not_an_earlier_stage")
    end

    apply!(from: from, to: target_stage.to_s, direction: "backward", reason: reason.to_s.strip)
  end

  private

  # Forward: admins, the quality manager, the record owner, or someone assigned
  # to the CURRENT stage.
  def ensure_can_move_forward!
    return if platform_admin? || company_manager? || record_owner? || stage_assignee?

    raise NotPermitted, I18n.t("documenter.errors.not_permitted_forward")
  end

  # Backward is a separate, narrower permission: admins, the quality manager, or
  # someone assigned to the current stage. Never the owner by default.
  def ensure_can_move_backward!
    return if platform_admin? || company_manager? || stage_assignee?

    raise NotPermitted, I18n.t("documenter.errors.not_permitted_backward")
  end

  def platform_admin?
    @user&.platform_admin?
  end

  def company_manager?
    cu = @user&.company_user
    cu.present? && cu.company_id == @record.company_id &&
      (cu.has_admin_privileges? || cu.company_quality_manager?)
  end

  def record_owner?
    @user.present? && @record.owner_user_id == @user.id
  end

  def stage_assignee?
    return false if @user.nil?

    @record.stage_assignees.for_stage(@record.stage_key).exists?(user_id: @user.id)
  end

  def apply!(from:, to:, direction:, reason:)
    ActiveRecord::Base.transaction do
      @record.stage_transitions.create!(
        from_stage: from, to_stage: to, direction: direction,
        actor_user: @user, reason: reason
      )
      # stage_entered_at is the clock the lateness maths reads.
      @record.update!(current_stage: to, stage_entered_at: Time.current)
    end

    AuditLogService.log_action(
      actor_user: @user, company: @company,
      action: direction == "forward" ? "PP_STAGE_ADVANCE" : "PP_STAGE_RETURN",
      entity_type: "pp_record", entity_id: @record.id,
      payload: { from: from, to: to, reason: reason }
    )

    @record
  end
end
