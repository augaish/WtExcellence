class AssignmentEvaluation < ApplicationRecord
  belongs_to :assessment, foreign_key: "assessment_id"
  belongs_to :evaluator, class_name: "User", foreign_key: "evaluator_id"

  validates :evaluation_status, presence: true, inclusion: { in: %w[approved rejected auditor_reviewed reopened] }
  validates :score, numericality: { allow_nil: true }
  validates :feedback, length: { maximum: 300, allow_blank: true }

  enum :evaluation_status, {
    approved: "approved",
    rejected: "rejected",
    auditor_reviewed: "auditor_reviewed",
    reopened: "reopened"
  }
end
