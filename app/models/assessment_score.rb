class AssessmentScore < ApplicationRecord
  belongs_to :assessment
  belongs_to :tool_subcheckpoint

  validates :assessment_id, uniqueness: { scope: :tool_subcheckpoint_id }
  validates :score, numericality: { allow_nil: true }
  validates :percentage_score, numericality: { allow_nil: true }
end
