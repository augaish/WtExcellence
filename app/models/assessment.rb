class Assessment < ApplicationRecord
  belongs_to :tool_clause
  belongs_to :company
  belongs_to :last_edited_by_user, class_name: "User", foreign_key: "last_edited_by_user_id", optional: true

  has_many :assessment_scores, dependent: :destroy
  has_many :assessment_users, dependent: :destroy
  has_many :users, through: :assessment_users
  has_many :evidence_attachments, as: :attachable, dependent: :destroy
  has_many :linked_uploads, through: :evidence_attachments, source: :upload
  has_many :assignment_evaluations, dependent: :destroy

  validates :tool_clause_id, uniqueness: { scope: :company_id }
  validates :status, presence: true, inclusion: {
    in: %w[not_started in_drafts under_review approved needs_changes]
  }

  # Convenience accessors
  delegate :clause, :tool, to: :tool_clause

  def score_for(subcheckpoint)
    assessment_scores.find_by(tool_subcheckpoint_id: subcheckpoint.id)
  end

  def contributors
    assessment_users.where(role: "contributor").includes(:user)
  end

  def auditor_user
    assessment_users.find_by(role: "auditor")&.user
  end

  def contributors_for_checklist_item(checklist_item_id)
    assessment_users.where(role: "contributor", checklist_item_id: checklist_item_id).includes(:user)
  end
end
