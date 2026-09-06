# A process diagram belonging to a record or a process.
#
# to_contract emits exactly the shape the efficiency evaluator expects, so the
# two halves of the feature share one vocabulary and nothing is re-keyed.
class PpDiagram < ApplicationRecord
  OWNER_TYPES = %w[PpRecord PpProcess].freeze

  belongs_to :company
  belongs_to :owner, polymorphic: true

  has_many :elements, -> { order(:position, :created_at) },
    class_name: "PpDiagramElement", foreign_key: "pp_diagram_id", dependent: :destroy
  has_many :flows, class_name: "PpDiagramFlow", foreign_key: "pp_diagram_id", dependent: :destroy

  validates :name, length: { maximum: 250 }
  validates :owner_type, inclusion: { in: OWNER_TYPES }
  validate :owner_must_be_same_company

  # Most recent first, as specified.
  scope :recent_first, -> { order(created_at: :desc) }

  def display_name
    name.presence || I18n.t("architect.untitled_diagram")
  end

  # Distinct swimlanes, organisation pools first and the external pool last.
  def pools
    names = elements.map(&:pool).uniq
    internal = names.reject { |n| n == PpDiagramElement::EXTERNAL_POOL }
    internal + (names.include?(PpDiagramElement::EXTERNAL_POOL) ? [ PpDiagramElement::EXTERNAL_POOL ] : [])
  end

  # The evaluation contract. Keys are strings so the evaluator can be fed either
  # this or a plain parsed JSON payload.
  def to_contract
    {
      "elements" => elements.map do |e|
        {
          "type" => e.element_type,
          "title" => e.title,
          "performer" => e.performer,
          "desc" => e.description,
          "input" => e.input,
          "output" => e.output,
          "trigger" => e.trigger_text,
          "scope" => e.scope,
          "flowLabel" => e.flow_label
        }
      end,
      "flows" => flows.map(&:to_contract),
      "trigger" => trigger_text,
      "inputsSummary" => inputs_summary,
      "outputsSummary" => outputs_summary
    }
  end

  # Summary fields live on the process card when the diagram hangs off a
  # process, so they are inherited rather than typed twice.
  def effective_summary
    {
      trigger: trigger_text.presence || inherited(:trigger_text),
      inputs: inputs_summary.presence || inherited(:inputs),
      outputs: outputs_summary.presence || inherited(:outputs)
    }
  end

  private

  def inherited(field)
    return nil unless owner.is_a?(PpProcess)

    owner.public_send(field) if owner.respond_to?(field)
  end

  def owner_must_be_same_company
    return if owner.nil? || !owner.respond_to?(:company_id) || owner.company_id == company_id

    errors.add(:owner, I18n.t("architect.errors.owner_other_company"))
  end
end
