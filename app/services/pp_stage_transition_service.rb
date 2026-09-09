# Moves records through the lifecycle, and is the single place the rules are
# enforced. The client never picks a destination: it asks to go forward, or to
# return to a named earlier stage with a reason. Everything else is derived.
#
# Guarantees:
#   * forward goes to exactly ONE computed stage — a crafted request cannot
#     skip ahead
#   * forward is allowed only to the stage's actor (see PpStage), or to a P&P
#     Manager / admin
#   * a stage with open work (a task handed to someone) cannot be left until
#     that work comes back
#   * an approval-chain stage cannot be left until every unit has approved;
#     Stakeholder Review alone may be skipped when nobody was asked
#   * backward is allowed only to an earlier stage ON THIS RECORD'S ROUTE, only
#     for a P&P Manager / admin, and always with a reason
#   * every move writes a transition row and stamps stage_entered_at, which is
#     what the duration/lateness maths reads
class PpStageTransitionService
  class TransitionError < StandardError; end
  class NotPermitted < TransitionError; end
  class InvalidTransition < TransitionError; end
  class ApprovalsPending < TransitionError; end
  class WorkOutstanding < TransitionError; end

  Result = Struct.new(:moved, :skipped, :errors, keyword_init: true) do
    def success? = errors.empty?
  end

  def self.advance(record:, user:, company:, skip_stakeholders: false)
    new(record: record, user: user, company: company).advance(skip_stakeholders: skip_stakeholders)
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

  # Who runs the flows: platform admins, company admins and P&P Managers.
  def self.manager?(user, company)
    return false if user.nil?
    return true if user.platform_admin?

    cu = user.company_user
    cu.present? && cu.company_id == company.id && (cu.company_admin? || cu.pp_manager?)
  end

  def initialize(record:, user:, company:)
    @record = record
    @user = user
    @company = company
  end

  def advance(skip_stakeholders: false)
    ensure_can_move_forward!

    from = @record.stage_key
    to = @record.next_stage_key
    raise InvalidTransition, I18n.t("documenter.errors.no_next_stage") if to.blank?

    # Work handed to someone must come back before the stage is left.
    if @record.stage_tasks.for_stage(from).open.exists?
      raise WorkOutstanding, I18n.t("documenter.errors.work_outstanding")
    end

    if PpStage.approval_stage?(from) && !@record.approvals_complete?(from)
      unless from == "s2_stakeholders" && skip_stakeholders && @record.stage_approvals.for_stage(from).none?
        raise ApprovalsPending, I18n.t("documenter.errors.approvals_pending")
      end
    end

    # Publishing has its own door (RecordPublisher), so the terminal stage is
    # never reached by a plain "forward".
    if PpStage.terminal?(to) && !@record.glossary?
      raise InvalidTransition, I18n.t("documenter.errors.publish_via_publisher")
    end

    apply!(from: from, to: to, direction: "forward", reason: nil)
  end

  def return_to(target_stage, reason)
    ensure_can_move_backward!

    if reason.to_s.strip.blank?
      raise InvalidTransition, I18n.t("documenter.errors.reason_required")
    end

    from = @record.stage_key
    unless PpStage.backward?(from, target_stage, record_type: @record.record_type)
      raise InvalidTransition, I18n.t("documenter.errors.not_an_earlier_stage")
    end

    apply!(from: from, to: target_stage.to_s, direction: "backward", reason: reason.to_s.strip)
  end

  # Used by RecordPublisher once the publishing conditions are met.
  def publish!
    from = @record.stage_key
    to = @record.next_stage_key
    raise InvalidTransition, I18n.t("documenter.errors.no_next_stage") unless to && PpStage.terminal?(to)

    apply!(from: from, to: to, direction: "forward", reason: nil)
  end

  private

  def manager?
    self.class.manager?(@user, @company)
  end

  # Forward: the stage's own actor, or a manager.
  def ensure_can_move_forward!
    return if manager? || stage_actor?

    raise NotPermitted, I18n.t("documenter.errors.not_permitted_forward")
  end

  # Backward: managers only. Unit heads push work back to a person (a task),
  # never the record to a stage.
  def ensure_can_move_backward!
    return if manager?

    raise NotPermitted, I18n.t("documenter.errors.not_permitted_backward")
  end

  def stage_actor?
    return false if @user.nil?

    case PpStage.actor_of(@record.stage_key)
    when :verifier then @record.verifier_user_id == @user.id
    when :unit_head then @record.owning_unit_head&.id == @user.id
    else false
    end
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
