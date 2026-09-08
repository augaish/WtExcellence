# One numbered step of a procedure (خطوات الإجراء).
#
# The responsible party is a job position, not a person: a procedure outlives
# whoever currently holds the post, which is the same reason the DoA delegates
# «للمنصب وليس للشخص».
class PpProcessStep < ApplicationRecord
  belongs_to :pp_process, class_name: "PpProcess"
  belongs_to :responsible_org_unit, class_name: "OrgUnit", optional: true

  # The diagram task drawn from this step, if the diagram has been generated.
  # A step that no longer exists has no business in the picture.
  has_one :diagram_element, class_name: "PpDiagramElement", foreign_key: "pp_process_step_id", dependent: :destroy

  # The association is consulted on create, before any element exists, and
  # Rails caches that nil on the instance. A later destroy of the same object
  # would trust the cache and leave the element behind, so it is reset first.
  before_destroy(prepend: true) { association(:diagram_element).reset }

  after_save :push_changes_to_element

  # Durations are entered per step in whatever unit suits it; the process total
  # is summed in minutes so mixed units add up correctly.
  UNITS = %w[minutes hours days].freeze

  MINUTES_PER_UNIT = {
    "minutes" => 1,
    "hours" => 60,
    "days" => 60 * 8
  }.freeze

  validates :position, presence: true, numericality: { greater_than: 0 }
  validates :activity, length: { maximum: 300 }
  validates :responsible_title, length: { maximum: 250 }
  validates :system_used, length: { maximum: 250 }
  validates :duration_unit, inclusion: { in: UNITS }, allow_blank: true
  validates :duration_value, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :duration_needs_a_unit
  validate :responsible_unit_must_be_same_company

  scope :ordered, -> { order(:position, :created_at) }

  # A working day is eight hours: the process card quotes totals in days, and a
  # step measured in days means working days, not elapsed ones.
  def duration_in_minutes
    return nil if duration_value.blank? || duration_unit.blank?

    duration_value * MINUTES_PER_UNIT.fetch(duration_unit, 1)
  end

  def responsible_label(locale = I18n.locale)
    responsible_title.presence || responsible_org_unit&.display_name(locale) || ""
  end

  private

  def push_changes_to_element
    return if DiagramStepSync.syncing?
    # Queried rather than read through the association, so nothing is cached
    # on a step that has no element yet.
    return unless PpDiagramElement.exists?(pp_process_step_id: id)
    return unless saved_change_to_activity? || saved_change_to_responsible_title? ||
                  saved_change_to_description? || saved_change_to_position?

    DiagramStepSync.step_to_element(self)
  end

  def duration_needs_a_unit
    return if duration_value.blank? || duration_unit.present?

    errors.add(:duration_unit, I18n.t("process_steps.errors.unit_required"))
  end

  def responsible_unit_must_be_same_company
    return if responsible_org_unit.nil? || pp_process.nil?
    return if responsible_org_unit.company_id == pp_process.company_id

    errors.add(:responsible_org_unit, I18n.t("process_steps.errors.other_company"))
  end
end
