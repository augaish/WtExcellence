# One clause of a policy: a main clause, or a sub-clause beneath one. Written
# by the reviewer the unit head picks, commented on by the P&P Manager's team.
class PpRecordClause < ApplicationRecord
  belongs_to :pp_record, class_name: "PpRecord"
  belongs_to :parent, class_name: "PpRecordClause", optional: true
  has_many :children, -> { ordered }, class_name: "PpRecordClause", foreign_key: "parent_id", dependent: :destroy
  has_many :comments, -> { order(:created_at) }, class_name: "PpClauseComment", foreign_key: "pp_record_clause_id", dependent: :destroy

  validates :position, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :title, length: { maximum: 300 }
  validate :must_have_content
  validate :parent_must_be_a_main_clause_of_same_record

  scope :ordered, -> { order(:position, :created_at) }
  scope :main, -> { where(parent_id: nil) }

  before_validation :assign_position

  def main?
    parent_id.nil?
  end

  # 1, 2, 3 for main clauses; 1.1, 1.2 beneath them.
  def number
    main? ? position.to_s : "#{parent.position}.#{position}"
  end

  def open_comments
    comments.where(resolved_at: nil)
  end

  private

  def assign_position
    return if position.present? && position.positive?

    siblings = PpRecordClause.where(pp_record_id: pp_record_id, parent_id: parent_id)
    self.position = siblings.maximum(:position).to_i + 1
  end

  def must_have_content
    return if title.to_s.strip.present? || body.to_s.strip.present?

    errors.add(:base, I18n.t("documenter.clauses.errors.content_required"))
  end

  # Two levels only: a main clause and its sub-clauses.
  def parent_must_be_a_main_clause_of_same_record
    return if parent.nil?

    errors.add(:parent_id, I18n.t("documenter.clauses.errors.parent_other_record")) if parent.pp_record_id != pp_record_id
    errors.add(:parent_id, I18n.t("documenter.clauses.errors.too_deep")) unless parent.main?
  end
end
