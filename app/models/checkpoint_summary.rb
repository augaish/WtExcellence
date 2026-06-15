class CheckpointSummary < ApplicationRecord
  belongs_to :tool_clause
  belongs_to :checklist_item
  belongs_to :tool_checkpoint
  belongs_to :company
  belongs_to :last_edited_by_user, class_name: "User", foreign_key: "last_edited_by_user_id", optional: true

  validates :tool_clause_id, uniqueness: { scope: [ :checklist_item_id, :tool_checkpoint_id, :company_id ] }
  validates :summary, length: { maximum: 100 }, allow_blank: true
end
