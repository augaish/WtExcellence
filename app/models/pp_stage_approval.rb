# One org unit's approval within an approval-chain stage (s2_stakeholders,
# s4_final). requested_at is stamped when the unit is added to the chain;
# received_at when someone marks it received. Both are system timestamps.
class PpStageApproval < ApplicationRecord
  belongs_to :pp_record, class_name: "PpRecord"
  belongs_to :org_unit
  belongs_to :requested_by, class_name: "User", optional: true
  belongs_to :received_by, class_name: "User", optional: true

  validates :stage_key, presence: true, inclusion: { in: PpStage::KEYS }
  validates :requested_at, presence: true
  validates :org_unit_id, uniqueness: { scope: [ :pp_record_id, :stage_key ] }

  scope :for_stage, ->(key) { where(stage_key: key) }
  scope :pending, -> { where(received_at: nil) }
  scope :received, -> { where.not(received_at: nil) }

  def received?
    received_at.present?
  end

  # Working days this unit has taken (or took) to respond.
  def elapsed_working_days(company)
    WorkingDaysService.between(company, requested_at, received_at || Time.current)
  end

  # Whether THIS unit is late against the stage target — the per-unit late
  # column the product owner asked for on the final-approvals screen.
  def late?(company, target_days)
    return false if target_days.to_i <= 0

    elapsed_working_days(company) > target_days.to_i
  end
end
