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
  # The procedure step this task was drawn from, if any. Edits to a linked
  # element's title, performer or description are written back to the step.
  belongs_to :pp_process_step, class_name: "PpProcessStep", optional: true

  after_save :push_changes_to_step
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

  # Performers are LANES inside the organisation's own pool. Only an external
  # participant has a pool of its own. This distinction is what BPMN draws:
  # sequence flow may cross lanes within a pool, and only crossing between
  # pools needs a message flow. Treating every performer as a pool — as this
  # once did — flagged an ordinary hand-off from Procurement to Finance as an
  # external crossing.
  def pool
    external? ? EXTERNAL_POOL : DEFAULT_POOL
  end

  # The swimlane the element is drawn in.
  def lane
    return EXTERNAL_POOL if external?

    performer.presence || DEFAULT_POOL
  end

  def type_label(locale = I18n.locale)
    I18n.t("architect.element_types.#{element_type}", locale: locale, default: element_type)
  end

  private

  # Guarded against echo: the step's own callback writes back here, and the
  # flag stops the two from updating each other forever.
  def push_changes_to_step
    return if pp_process_step.nil? || DiagramStepSync.syncing?
    return unless saved_change_to_title? || saved_change_to_performer? || saved_change_to_description?

    DiagramStepSync.element_to_step(self)
  end
end
