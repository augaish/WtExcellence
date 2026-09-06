# Who may act on a record at a particular stage, in addition to admins, the
# quality manager, and the record owner.
class PpStageAssignee < ApplicationRecord
  belongs_to :pp_record, class_name: "PpRecord"
  belongs_to :user

  validates :stage_key, presence: true, inclusion: { in: PpStage::KEYS }
  validates :user_id, uniqueness: { scope: [ :pp_record_id, :stage_key ] }

  scope :for_stage, ->(key) { where(stage_key: key) }
end
