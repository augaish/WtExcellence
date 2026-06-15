class AssessmentUser < ApplicationRecord
  belongs_to :assessment
  belongs_to :user
  belongs_to :checklist_item, optional: true
  belongs_to :assigner_user, class_name: "User", foreign_key: "assigner_user_id", optional: true

  validates :assessment_id, uniqueness: { scope: [ :user_id, :checklist_item_id ] }
  validates :role, presence: true, inclusion: { in: %w[contributor auditor] }

  delegate :tool_clause, :company, to: :assessment
end
