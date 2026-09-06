# A connector between two elements.
#
#   sequence - the normal flow WITHIN one pool
#   message  - the only legal way to cross into an external participant
#
# A sequence flow that crosses pools is a real modelling error; it is not
# blocked here (the user may be mid-edit) but the evaluator scores it down and
# the renderer draws it so the mistake is visible.
class PpDiagramFlow < ApplicationRecord
  KINDS = %w[sequence message].freeze

  belongs_to :pp_diagram
  belongs_to :from_element, class_name: "PpDiagramElement"
  belongs_to :to_element, class_name: "PpDiagramElement"

  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :label, length: { maximum: 200 }
  validate :elements_belong_to_the_same_diagram
  validate :cannot_connect_an_element_to_itself

  scope :sequences, -> { where(kind: "sequence") }
  scope :messages, -> { where(kind: "message") }

  def crosses_pools?
    from_element.pool != to_element.pool
  end

  # The shape the evaluator consumes: { kind:, from: { pool: }, to: { pool: } }
  def to_contract
    { "kind" => kind, "from" => { "pool" => from_element.pool }, "to" => { "pool" => to_element.pool } }
  end

  private

  def elements_belong_to_the_same_diagram
    return if from_element.nil? || to_element.nil?
    return if from_element.pp_diagram_id == pp_diagram_id && to_element.pp_diagram_id == pp_diagram_id

    errors.add(:base, I18n.t("architect.errors.flow_other_diagram"))
  end

  def cannot_connect_an_element_to_itself
    return if from_element_id.blank? || from_element_id != to_element_id

    errors.add(:to_element_id, I18n.t("architect.errors.flow_self"))
  end
end
