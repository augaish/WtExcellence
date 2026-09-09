# An org unit that takes part in delivering a service, alongside the owning
# unit that provides it.
class PpRecordParticipant < ApplicationRecord
  belongs_to :pp_record, class_name: "PpRecord"
  belongs_to :org_unit

  validates :org_unit_id, uniqueness: { scope: :pp_record_id }
end
