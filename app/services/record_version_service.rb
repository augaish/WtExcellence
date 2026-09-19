# "Update existing": opens the next version of a record as a fresh draft.
#
# Everything the reader would expect to still be true is copied - titles,
# description, scope, ownership, the process, the cards, the links. What is
# NOT copied is what belongs to the old issue alone: its stage, its approvals,
# its code's version tail, and its reason for change, which the author must
# write anew. The old version stays where it is, read-only, as history.
class RecordVersionService
  COPIED_ATTRIBUTES = %w[
    record_type title_en title_ar description scope owner_user_id owner_org_unit_id
    pp_process_id classification counterparty effective_date
    trigger_text inputs outputs predecessor_record_id successor_record_id frequency
    total_time_value total_time_unit automation_status technical_systems kpis sequence_number
    service_type requirements beneficiaries delivery_period channels delivery_stages
    counterparty_kind counterparty_org_unit_id language
  ].freeze

  class NotLatest < StandardError; end

  def self.open_next(record, actor: nil)
    new(record, actor: actor).open_next
  end

  def initialize(record, actor: nil)
    @record = record
    @actor = actor
  end

  def open_next
    raise NotLatest if record.next_version.present?

    PpRecord.transaction do
      successor = record.company.pp_records.new(record.attributes.slice(*COPIED_ATTRIBUTES))
      successor.previous_version = record
      successor.version_number = record.version_number.to_i + 1
      successor.version_label = "v#{successor.version_number}"
      successor.code = RecordCodeService.next_version_code(record.code, successor.version_number)
      successor.change_summary = nil
      successor.current_stage = nil
      successor.stage_entered_at = nil
      successor.save!(validate: false)

      copy_content(record, successor)
      record.links.find_each { |link| successor.links.create!(linked_record_id: link.linked_record_id, kind: link.kind) }
      record.participants.find_each { |p| successor.participants.create!(org_unit_id: p.org_unit_id) }
      record.service_levels.find_each do |level|
        successor.service_levels.create!(level.attributes.except("id", "pp_record_id", "created_at", "updated_at"))
      end

      successor
    end
  end

  private

  attr_reader :record, :actor

  COPIED_CLAUSE = %w[position title body].freeze
  COPIED_STEP = %w[position activity description responsible_title responsible_org_unit_id duration_value duration_unit system_used].freeze
  COPIED_DECISION = %w[item decision sort_order authority_id].freeze
  COPIED_HOLDER = %w[level holder_title org_unit_id condition sort_order].freeze

  # What the document says travels with it: clauses (with their sub-clauses),
  # steps with their decisions and holders, references and glossary terms.
  # The next version starts as the last one and is edited from there.
  def copy_content(from, to)
    clause_ids = {}
    from.clauses.main.each do |clause|
      copy = to.clauses.create!(clause.attributes.slice(*COPIED_CLAUSE))
      clause_ids[clause.id] = copy.id
      clause.children.each { |sub| to.clauses.create!(sub.attributes.slice(*COPIED_CLAUSE).merge("parent_id" => copy.id)) }
    end

    step_ids = {}
    from.steps.each do |step|
      copy = to.steps.create!(step.attributes.slice(*COPIED_STEP))
      step_ids[step.id] = copy.id
    end

    from.operational_authorities.each do |decision|
      copy = to.operational_authorities.create!(decision.attributes.slice(*COPIED_DECISION)
        .merge("pp_process_step_id" => step_ids[decision.pp_process_step_id]))
      decision.assignments.each { |holder| copy.assignments.create!(holder.attributes.slice(*COPIED_HOLDER)) }
    end

    from.form_fields.each do |field|
      to.form_fields.create!(field.attributes.slice("position", "label_en", "label_ar", "field_type", "required", "options", "columns", "hint"))
    end
    from.references.each { |ref| to.references.create!(ref.attributes.slice("clause_id", "name", "source", "sort_order")) }
    from.record_terms.each { |term| to.record_terms.create!(glossary_term_id: term.glossary_term_id, sort_order: term.sort_order) }
  end
end
