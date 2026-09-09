# The actions people take inside a stage, as opposed to moving between stages
# (PpStageTransitionService). Each is small and named after what the person
# does: hand work to someone, send it back, ask units to approve, answer as a
# unit head, re-send after a rejection.
class DocumenterActions
  class NotPermitted < StandardError; end
  class Invalid < StandardError; end

  def initialize(record:, user:, company:)
    @record = record
    @user = user
    @company = company
  end

  # ---- Tasks ---------------------------------------------------------------

  # A unit head hands the clauses/steps to one of their reporters; a P&P
  # Manager hands the review to someone on their team; a designer or a
  # publisher is named the same way.
  def assign_task(assignee, note: nil)
    ensure_can_hand_out!
    raise Invalid, I18n.t("documenter.errors.assignee_not_eligible") unless eligible_assignee?(assignee)

    @record.stage_tasks.for_stage(@record.stage_key).open.update_all(submitted_at: Time.current)
    task = @record.stage_tasks.create!(stage_key: @record.stage_key, user: assignee, assigned_by: @user,
      assigned_at: Time.current, note: note.presence)
    notify(assignee, "record_task_assigned")
    task
  end

  # The person with the task hands it back to whoever gave it.
  def submit_task(note: nil)
    task = @record.stage_tasks.for_stage(@record.stage_key).open.for_user(@user).first
    raise NotPermitted, I18n.t("documenter.errors.no_open_task") if task.nil?

    task.submit!(note: note)
    notify(task.assigned_by, "record_task_submitted") if task.assigned_by
    task
  end

  # ---- Approval chains -----------------------------------------------------

  # The P&P Manager names the units (heads) to ask, in groups: group 1 is asked
  # now, group 2 once group 1 has approved, and so on. Optional silence period.
  def request_approvals(unit_ids_by_group, auto_days: nil)
    ensure_manager!
    stage = @record.stage_key
    raise Invalid, I18n.t("documenter.flash.not_an_approval_stage") unless PpStage.approval_stage?(stage)

    if auto_days.present?
      @record.update!(auto_approve_days: auto_days.to_i)
    end

    unit_ids_by_group.each do |group, unit_ids|
      Array(unit_ids).reject(&:blank?).each do |unit_id|
        unit = @company.org_units.find_by(id: unit_id) or next
        approval = @record.stage_approvals.find_or_initialize_by(stage_key: stage, org_unit: unit)
        approval.requested_at ||= Time.current
        approval.requested_by ||= @user
        approval.sequence_group = group.to_i.clamp(1, 20)
        approval.auto_approve_at = deadline_for(auto_days)
        approval.save!
        notify(unit.head_user, "record_approval_requested") if unit.head_user && approval.turn?
      end
    end
  end

  # A unit head answers for their unit. Only when it is their group's turn.
  def answer_approval(approval, decision, comment: nil)
    raise NotPermitted, I18n.t("documenter.errors.not_the_unit_head") unless can_answer?(approval)
    raise Invalid, I18n.t("documenter.errors.not_your_turn") unless approval.turn?
    raise Invalid, I18n.t("documenter.errors.comment_required_on_reject") if decision == "rejected" && comment.to_s.strip.blank?

    approval.answer!(decision, by: @user, comment: comment)
    after_answer(approval)
    approval
  end

  # Silence past the deadline counts as approval. Called by the daily job.
  def auto_approve_overdue!
    @record.stage_approvals.for_stage(@record.stage_key).pending
      .where("auto_approve_at IS NOT NULL AND auto_approve_at <= ?", Time.current)
      .find_each do |approval|
        next unless approval.turn?

        approval.answer!("auto_approved", by: nil)
        after_answer(approval)
      end
  end

  # After a rejection the P&P Manager edits, then sends again: to the units
  # that refused, or to all of them.
  def resend_approvals(scope: "rejected")
    ensure_manager!
    approvals = @record.stage_approvals.for_stage(@record.stage_key)
    approvals = approvals.rejected if scope == "rejected"
    approvals.find_each do |approval|
      approval.resend!(by: @user, auto_days: @record.auto_approve_days, company: @company)
      notify(approval.org_unit.head_user, "record_approval_requested") if approval.org_unit.head_user && approval.turn?
    end
  end

  def remove_approval(approval)
    ensure_manager!
    approval.destroy
  end

  # ---- Publishing choices --------------------------------------------------

  def choose_publish_mode(mode)
    ensure_manager!
    raise Invalid, I18n.t("documenter.errors.unknown_publish_mode") unless PpRecord::PUBLISH_MODES.include?(mode)

    @record.update!(publish_mode: mode)
  end

  # The publisher pastes where the document went, and presses Publish.
  def submit_publication(link)
    raise Invalid, I18n.t("documenter.errors.link_required") if link.to_s.strip.blank?

    @record.update!(published_link: link.to_s.strip)
    submit_task
  end

  # ---- Who may do what -----------------------------------------------------

  def manager?
    PpStageTransitionService.manager?(@user, @company)
  end

  def unit_head?
    @user.present? && @record.owning_unit_head&.id == @user.id
  end

  # The people a unit head may hand work to: their reporters, directly or down
  # the chain. A P&P Manager may hand review work to anyone on their own team
  # (the unit they head, or a quality manager).
  def eligible_assignees
    if PpStage.actor_of(@record.stage_key) == :unit_head && unit_head? && !manager?
      reporters_of(@record.owner_org_unit)
    elsif manager?
      @company.users.where.not(id: @user.id).order(:name)
    else
      User.none
    end
  end

  def can_answer?(approval)
    @user.present? && approval.org_unit.head_user_id == @user.id && approval.pending?
  end

  private

  def ensure_manager!
    raise NotPermitted, I18n.t("documenter.flash.no_permission") unless manager?
  end

  def ensure_can_hand_out!
    actor = PpStage.actor_of(@record.stage_key)
    return if manager?
    return if actor == :unit_head && unit_head?

    raise NotPermitted, I18n.t("documenter.flash.no_permission")
  end

  def eligible_assignee?(user)
    user.present? && eligible_assignees.exists?(id: user.id)
  end

  def reporters_of(unit)
    return User.none if unit.nil?

    @company.users.where(org_unit_id: [ unit.id ] + unit.descendant_ids).where.not(id: @user.id).order(:name)
  end

  def deadline_for(auto_days)
    return nil if auto_days.blank?

    WorkingDaysService.new(@company).add_working_days(Time.current, auto_days.to_i)
  end

  # Once a unit answers, the next group in sequence is asked; once everybody
  # has approved, the record moves on by itself.
  def after_answer(approval)
    if approval.approved?
      @record.stage_approvals.for_stage(approval.stage_key).pending.find_each do |pending|
        next unless pending.turn? && pending.org_unit.head_user

        notify(pending.org_unit.head_user, "record_approval_requested")
      end
      if @record.approvals_complete?(approval.stage_key)
        PpStageTransitionService.new(record: @record, user: nil, company: @company)
          .send(:apply!, from: @record.stage_key, to: @record.next_stage_key, direction: "forward", reason: nil)
      end
    else
      managers.each { |m| notify(m, "record_approval_rejected", unit: approval.org_unit.display_name) }
    end
  end

  def managers
    ids = @company.company_users.where(pp_manager: true).pluck(:user_id) +
      @company.company_users.where(role: CompanyUser::ROLES[:company_admin]).pluck(:user_id)
    User.where(id: ids.uniq)
  end

  def notify(recipient, kind, unit: nil)
    return if recipient.nil?

    DocumenterNotifier.notify(recipient: recipient, record: @record, kind: kind, actor: @user, unit: unit)
  end
end
