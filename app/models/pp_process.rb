# One node of the Process Architecture.
#
# Level 0 is not a row: it is one of three fixed bands (managerial, core,
# support) that a level-1 process belongs to. Level 1 and level 2 are rows
# here. Level 3 — the procedure — is a governed record in Records, which
# links back to its level-2 parent. Each node carries a number within its
# parent so that the architecture number (1.2, 1.2.4) can be read off the tree.
class PpProcess < ApplicationRecord
  MAX_LEVEL = 2

  # Level 0. Order and numbers are fixed; the names may be changed per company.
  CATEGORIES = %w[management core support].freeze
  BAND_NUMBERS = { "management" => 1, "core" => 2, "support" => 3 }.freeze

  # دورية تنفيذ الإجراء
  FREQUENCIES = %w[on_demand daily weekly monthly quarterly semi_annual annual].freeze

  # حالة الأتمتة
  AUTOMATION_STATUSES = %w[manual partially_automated fully_automated].freeze

  TIME_UNITS = %w[minutes hours days].freeze

  belongs_to :company
  belongs_to :parent, class_name: "PpProcess", optional: true
  belongs_to :owner_org_unit, class_name: "OrgUnit", optional: true
  belongs_to :owner_user, class_name: "User", optional: true
  belongs_to :predecessor_process, class_name: "PpProcess", optional: true
  belongs_to :successor_process, class_name: "PpProcess", optional: true

  has_many :children, -> { order(:sort_order, :created_at) },
    class_name: "PpProcess", foreign_key: "parent_id", dependent: :restrict_with_error
  has_many :steps, -> { ordered }, class_name: "PpProcessStep", foreign_key: "pp_process_id", dependent: :destroy
  has_many :authorities, -> { ordered }, class_name: "PpProcessAuthority", foreign_key: "pp_process_id", dependent: :destroy
  has_many :pp_records, class_name: "PpRecord", foreign_key: "pp_process_id", dependent: :nullify
  has_many :diagrams, -> { order(created_at: :desc) }, as: :owner, class_name: "PpDiagram", dependent: :destroy

  validates :level, presence: true,
    numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: MAX_LEVEL }
  validates :category, inclusion: { in: CATEGORIES }, allow_blank: true
  validates :category, presence: true, if: -> { level == 1 }
  validates :number, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :frequency, inclusion: { in: FREQUENCIES }, allow_blank: true
  validates :automation_status, inclusion: { in: AUTOMATION_STATUSES }, allow_blank: true
  validates :total_time_unit, inclusion: { in: TIME_UNITS }, allow_blank: true
  validates :total_time_value, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :code, length: { maximum: 50 }, allow_blank: true
  validates :code, uniqueness: { scope: :company_id }, allow_blank: true
  validates :name_en, length: { maximum: 250 }
  validates :name_ar, length: { maximum: 250 }
  validate :must_have_a_name
  validate :parent_must_be_same_company
  validate :cannot_be_own_ancestor
  validate :level_must_follow_parent

  before_validation :inherit_category_from_parent
  before_validation :assign_number
  before_validation :default_code_to_architecture_number

  scope :active, -> { where(active: true) }
  scope :roots, -> { where(parent_id: nil) }
  scope :ordered, -> { order(:sort_order, :code, :created_at) }
  scope :at_level, ->(level) { where(level: level) }

  # The total time the procedure takes, summed from its steps rather than typed.
  # Durations are captured by the system from the work itself, so a total cannot
  # drift from the steps it is meant to describe. Returns nil when no step names
  # a duration, in which case the typed total_time_value stands as a fallback.
  def computed_total_minutes
    durations = steps.filter_map(&:duration_in_minutes)
    return nil if durations.empty?

    durations.sum
  end

  # The computed total expressed in the unit the process card uses, so the card
  # reads the same way whether the steps were entered in minutes or days.
  def computed_total_in(unit)
    minutes = computed_total_minutes
    return nil if minutes.nil?

    per_unit = PpProcessStep::MINUTES_PER_UNIT.fetch(unit.to_s, 1)
    (minutes / per_unit.to_d).round(2)
  end

  # True when someone typed a total that the steps contradict. Surfaced as a
  # warning rather than an error: the steps may simply be incomplete.
  def total_time_disagrees_with_steps?
    return false if total_time_value.blank? || total_time_unit.blank?

    computed = computed_total_in(total_time_unit)
    computed.present? && computed != total_time_value
  end

  def display_name(locale = I18n.locale)
    primary, fallback = locale.to_s == "ar" ? [ name_ar, name_en ] : [ name_en, name_ar ]
    primary.presence || fallback.presence || code.presence || ""
  end

  # Category is authored on the top level; descendants inherit it.
  def effective_category
    return category if category.present?

    parent&.effective_category
  end

  def band_number
    BAND_NUMBERS[effective_category]
  end

  # 1.2 for a level-1 process, 1.2.4 for a level-2 one: the band, then each
  # node's number down the tree. A procedure appends its own sequence.
  def architecture_number
    parts = [ band_number ]
    parts.concat(ancestors.map(&:number))
    parts << number
    return nil if parts.any?(&:nil?)

    parts.join(".")
  end

  def ancestors
    chain = []
    node = parent
    while node && chain.size <= MAX_LEVEL + 2
      break if chain.any? { |a| a.id == node.id }

      chain.unshift(node)
      node = node.parent
    end
    chain
  end

  private

  def inherit_category_from_parent
    self.category = parent.effective_category if level.to_i > 1 && parent
  end

  # The next free number among the siblings, so numbering never needs typing.
  def assign_number
    return if number.present? || company_id.nil?

    siblings = company.pp_processes.where(parent_id: parent_id)
    siblings = siblings.where(category: category) if parent_id.nil?
    self.number = siblings.maximum(:number).to_i + 1
  end

  def default_code_to_architecture_number
    self.code = architecture_number if code.blank?
  end

  def must_have_a_name
    return if name_en.to_s.strip.present? || name_ar.to_s.strip.present?

    errors.add(:base, I18n.t("process_architecture.errors.name_required"))
  end

  def parent_must_be_same_company
    return if parent.nil? || parent.company_id == company_id

    errors.add(:parent_id, I18n.t("process_architecture.errors.parent_other_company"))
  end

  def cannot_be_own_ancestor
    return if parent_id.blank?

    if parent_id == id
      errors.add(:parent_id, I18n.t("process_architecture.errors.parent_self"))
      return
    end

    node = parent
    seen = 0
    while node && seen <= MAX_LEVEL + 2
      if node.id == id
        errors.add(:parent_id, I18n.t("process_architecture.errors.parent_cycle"))
        return
      end
      node = node.parent
      seen += 1
    end
  end

  # A level-N process must sit directly under a level-(N-1) process; level 1 is
  # always a root.
  def level_must_follow_parent
    return if level.blank?

    if parent.nil?
      errors.add(:level, I18n.t("process_architecture.errors.root_must_be_level_one")) unless level == 1
    elsif parent.level.present? && level != parent.level + 1
      errors.add(:level, I18n.t("process_architecture.errors.level_must_follow_parent"))
    end
  end
end
