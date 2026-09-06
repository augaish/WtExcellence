# One move through the lifecycle. This table is the audit trail AND the clock:
# a stage's duration is measured between transition timestamps.
class PpStageTransition < ApplicationRecord
  DIRECTIONS = %w[forward backward].freeze

  belongs_to :pp_record, class_name: "PpRecord"
  belongs_to :actor_user, class_name: "User", optional: true

  validates :to_stage, presence: true, inclusion: { in: PpStage::KEYS }
  validates :from_stage, inclusion: { in: PpStage::KEYS }, allow_nil: true
  validates :direction, presence: true, inclusion: { in: DIRECTIONS }
  # A return must say why; going forward needs no justification.
  validates :reason, presence: true, if: -> { direction == "backward" }

  scope :chronological, -> { order(:created_at) }
  scope :backward, -> { where(direction: "backward") }
end
