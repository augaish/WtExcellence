# One element of a process diagram. The user adds these one at a time in a
# structured form; the picture is generated from them.
class PpDiagramElement < ApplicationRecord
  # The full element vocabulary, in the exact spelling the evaluator expects.
  EVENT_TYPES = %w[startEvent endEvent].freeze
  TASK_TYPES = %w[
    manualTask userTask serviceTask sendTask receiveTask businessRuleTask scriptTask
  ].freeze
  ARTIFACT_TYPES = %w[dataObject dataStore message textAnnotation].freeze
  TYPES = (EVENT_TYPES + TASK_TYPES + %w[gateway] + ARTIFACT_TYPES).freeze

  # Tasks that represent automated or system-assisted work.
  DIGITAL_TASK_TYPES = %w[
    serviceTask userTask sendTask receiveTask businessRuleTask scriptTask
  ].freeze

  SCOPES = %w[internal external].freeze

  # The pool an element with no named performer falls into.
  DEFAULT_POOL = "organisation".freeze
  EXTERNAL_POOL = "external".freeze

  belongs_to :pp_diagram
  has_many :outgoing_flows, class_name: "PpDiagramFlow",
    foreign_key: "from_element_id", dependent: :destroy
  has_many :incoming_flows, class_name: "PpDiagramFlow",
    foreign_key: "to_element_id", dependent: :destroy

  validates :element_type, presence: true, inclusion: { in: TYPES }
  validates :scope, presence: true, inclusion: { in: SCOPES }
  validates :title, length: { maximum: 300 }
  validates :performer, length: { maximum: 200 }

  scope :ordered, -> { order(:position, :created_at) }

  def task?
    TASK_TYPES.include?(element_type)
  end

  def gateway?
    element_type == "gateway"
  end

  def event?
    EVENT_TYPES.include?(element_type)
  end

  def artifact?
    ARTIFACT_TYPES.include?(element_type)
  end

  def external?
    scope == "external"
  end

  # Swimlanes are performers; anything external sits in its own pool, which is
  # what makes "sequence flow must not cross pools" checkable.
  def pool
    return EXTERNAL_POOL if external?

    performer.presence || DEFAULT_POOL
  end

  def type_label(locale = I18n.locale)
    I18n.t("architect.element_types.#{element_type}", locale: locale, default: element_type)
  end
end
