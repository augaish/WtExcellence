# One org unit's approval within an approval-chain stage (s2_stakeholders,
# s4_final). requested_at is stamped when the unit is added to the chain;
# received_at when its head answers (or when silence is taken as approval).
# Both are system timestamps.
#
# Units in the same sequence_group are asked together; a later group is asked
# only once every earlier group has approved. auto_approve_at is set when the
# P&P Manager chose a silence period.
class PpStageApproval < ApplicationRecord
  DECISIONS = %w[approved rejected auto_approved].freeze

  belongs_to :pp_record, class_name: "PpRecord"
  belongs_to :org_unit
  belongs_to :requested_by, class_name: "User", optional: true
  belongs_to :received_by, class_name: "User", optional: true

  validates :stage_key, presence: true, inclusion: { in: PpStage::KEYS }
  validates :requested_at, presence: true
  validates :org_unit_id, uniqueness: { scope: [ :pp_record_id, :stage_key ] }
  validates :decision, inclusion: { in: DECISIONS }, allow_blank: true
  validates :sequence_group, numericality: { only_integer: true, greater_than: 0 }
  validates :comment, length: { maximum: 5000 }

  scope :for_stage, ->(key) { where(stage_key: key) }
  scope :pending, -> { where(decision: nil) }
  scope :received, -> { where.not(decision: nil) }
  scope :approved, -> { where(decision: %w[approved auto_approved]) }
  scope :rejected, -> { where(decision: "rejected") }
  scope :ordered, -> { order(:sequence_group, :requested_at) }

  def approved?
    decision.in?(%w[approved auto_approved])
  end

  def rejected?
    decision == "rejected"
  end

  def pending?
    decision.nil?
  end

  # Green / red / orange, as the P&P Manager's screen shows it.
  def status_colour
    return "green" if approved?
    return "red" if rejected?

    "orange"
  end

  # Whether this unit's turn has come: the first group always; a later group
  # once every earlier group has approved.
  def turn?
    return true if sequence_group == 1

    # NULL is "not answered", which SQL's NOT IN would silently drop.
    PpStageApproval.where(pp_record_id: pp_record_id, stage_key: stage_key)
      .where("sequence_group < ?", sequence_group)
      .where("decision IS NULL OR decision NOT IN (?)", %w[approved auto_approved]).none?
  end

  def answer!(decision, by:, comment: nil)
    update!(decision: decision, received_at: Time.current, received_by: by, comment: comment.presence)
  end

  # Sent again after a rejection: the old answer is cleared and the clock
  # restarts from now.
  def resend!(by:, auto_days: nil, company: nil)
    update!(decision: nil, received_at: nil, received_by: nil, comment: nil,
      requested_at: Time.current, requested_by: by,
      auto_approve_at: auto_days && company ? WorkingDaysService.new(company).add_working_days(Time.current, auto_days) : nil)
  end

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
