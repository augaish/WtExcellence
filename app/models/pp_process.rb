class PpProcess < ApplicationRecord
  MAX_LEVEL = 3

  # فئة الإجراء — set on level 1 and inherited downward for reporting.
  CATEGORIES = %w[core support management].freeze

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
  has_many :pp_records, class_name: "PpRecord", foreign_key: "pp_process_id", dependent: :nullify

  validates :level, presence: true,
    numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: MAX_LEVEL }
  validates :category, inclusion: { in: CATEGORIES }, allow_blank: true
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

  scope :active, -> { where(active: true) }
  scope :roots, -> { where(parent_id: nil) }
  scope :ordered, -> { order(:sort_order, :code, :created_at) }
  scope :at_level, ->(level) { where(level: level) }

  def display_name(locale = I18n.locale)
    primary, fallback = locale.to_s == "ar" ? [ name_ar, name_en ] : [ name_en, name_ar ]
    primary.presence || fallback.presence || code.presence || ""
  end

  # Category is authored on the top level; descendants inherit it.
  def effective_category
    return category if category.present?

    parent&.effective_category
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
