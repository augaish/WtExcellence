# A reviewer's note on one clause, left during Initial Draft Review. Resolved
# by whoever fixes the clause; open comments are what the unit head sees.
class PpClauseComment < ApplicationRecord
  belongs_to :clause, class_name: "PpRecordClause", foreign_key: "pp_record_clause_id"
  belongs_to :user

  validates :body, presence: true, length: { maximum: 5000 }
  validates :stage_key, inclusion: { in: PpStage::KEYS }, allow_blank: true

  scope :open, -> { where(resolved_at: nil) }

  def resolved?
    resolved_at.present?
  end
end
