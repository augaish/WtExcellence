class ToolClause < ApplicationRecord
  # Validations
  validates :tool_id, uniqueness: { scope: :clause_id }
  validates :clause_id, uniqueness: true

  # Associations
  belongs_to :tool
  belongs_to :clause
  has_many :assessments, dependent: :destroy
  has_many :checkpoint_summaries, dependent: :destroy
end
