# What needs this person's hand right now, across every record: the records
# whose current stage they act in, the work handed to them, and the approvals
# their unit owes. Read by the Documenter worklist and nothing else decides
# it, so a person's list and their permissions can never disagree.
class DocumenterInbox
  Item = Struct.new(:record, :reason, keyword_init: true)

  def initialize(user:, company:)
    @user = user
    @company = company
  end

  def items
    @items ||= (stage_actor_items + task_items + approval_items).uniq { |i| [ i.record.id, i.reason ] }
  end

  def empty?
    items.empty?
  end

  private

  attr_reader :user, :company

  def active_records
    company.pp_records.active.latest.where.not(record_type: PpRecord::DOA_TYPES)
      .where.not(current_stage: PpStage::TERMINAL_KEYS).includes(:owner_org_unit)
  end

  # Verifier at Data Verification; unit head at Initial Draft Preparation;
  # managers everywhere a manager acts.
  def stage_actor_items
    manager = PpStageTransitionService.manager?(user, company)
    active_records.filter_map do |record|
      case PpStage.actor_of(record.stage_key)
      when :verifier
        Item.new(record: record, reason: :verify) if record.verifier_user_id == user.id || manager
      when :unit_head
        Item.new(record: record, reason: :prepare) if record.owning_unit_head&.id == user.id || manager
      when :pp_manager, :approvers, :publisher
        Item.new(record: record, reason: :manage) if manager
      end
    end
  end

  def task_items
    PpStageTask.open.for_user(user).joins(:pp_record).where(pp_records: { company_id: company.id })
      .includes(:pp_record).map { |task| Item.new(record: task.pp_record, reason: :task) }
  end

  def approval_items
    unit_ids = company.org_units.where(head_user_id: user.id).pluck(:id)
    return [] if unit_ids.empty?

    PpStageApproval.pending.where(org_unit_id: unit_ids).joins(:pp_record)
      .where(pp_records: { company_id: company.id })
      .includes(:pp_record).select(&:turn?)
      .select { |a| a.pp_record.stage_key == a.stage_key }
      .map { |a| Item.new(record: a.pp_record, reason: :approve) }
  end
end
