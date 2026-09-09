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
end
