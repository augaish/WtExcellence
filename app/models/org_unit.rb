class OrgUnit < ApplicationRecord
  MAX_LEVEL = OrgLevelDefinition::MAX_LEVEL

  belongs_to :company
  belongs_to :parent, class_name: "OrgUnit", optional: true
  belongs_to :org_group, optional: true
  belongs_to :head_user, class_name: "User", optional: true

  has_many :children, -> { order(:sort_order, :created_at) },
    class_name: "OrgUnit", foreign_key: "parent_id", dependent: :restrict_with_error
  has_many :members, class_name: "User", foreign_key: "org_unit_id", dependent: :nullify
  has_one :library_folder, class_name: "Folder", foreign_key: "org_unit_id", dependent: :nullify
  has_many :owned_processes, class_name: "PpProcess", foreign_key: "owner_org_unit_id", dependent: :nullify

  validates :level, presence: true,
    numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: MAX_LEVEL }
  validates :code, length: { maximum: 50 }, allow_blank: true
  validates :code, uniqueness: { scope: :company_id }, allow_blank: true
  validates :name_en, length: { maximum: 250 }
  validates :name_ar, length: { maximum: 250 }
  validates :email, length: { maximum: 255 }, allow_blank: true,
    format: { with: URI::MailTo::EMAIL_REGEXP }, if: -> { email.present? }
  validates :cost_center, length: { maximum: 100 }, allow_blank: true
  validate :must_have_a_name
  validate :parent_must_be_same_company
  validate :cannot_be_own_ancestor
  validate :parent_must_outrank_child

  scope :active, -> { where(active: true) }
  scope :roots, -> { where(parent_id: nil) }
  scope :ordered, -> { order(:level, :sort_order, :created_at) }
  scope :at_level, ->(level) { where(level: level) }

  def display_name(locale = I18n.locale)
    primary, fallback = locale.to_s == "ar" ? [ name_ar, name_en ] : [ name_en, name_ar ]
    primary.presence || fallback.presence || code.presence || ""
  end

  # Mandates are a repeatable free-text list ("+ add" in the UI).
  def mandate_list
    Array(mandates).map { |m| m.to_s.strip }.reject(&:blank?)
  end

  def mandate_list=(values)
    self.mandates = Array(values).map { |m| m.to_s.strip }.reject(&:blank?)
  end

  # Levels are numbered, never named: "Level 3" in the reader's language.
  def level_name(locale = I18n.locale)
    "#{I18n.t('org_structure.level', locale: locale)} #{level}"
  end

  # Root -> ... -> self, used for breadcrumbs. Guarded against cycles.
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

  def descendant_ids
    ids = []
    frontier = children.pluck(:id)
    while frontier.any?
      ids.concat(frontier)
      frontier = OrgUnit.where(parent_id: frontier).pluck(:id) - ids
    end
    ids
  end

  private

  def must_have_a_name
    return if name_en.to_s.strip.present? || name_ar.to_s.strip.present?

    errors.add(:base, I18n.t("org_structure.errors.unit_name_required"))
  end

  def parent_must_be_same_company
    return if parent.nil? || parent.company_id == company_id

    errors.add(:parent_id, I18n.t("org_structure.errors.parent_other_company"))
  end

  def cannot_be_own_ancestor
    return if parent_id.blank?

    if parent_id == id
      errors.add(:parent_id, I18n.t("org_structure.errors.parent_self"))
      return
    end

    node = parent
    seen = 0
    while node && seen <= MAX_LEVEL + 2
      if node.id == id
        errors.add(:parent_id, I18n.t("org_structure.errors.parent_cycle"))
        return
      end
      node = node.parent
      seen += 1
    end
  end

  # A unit reports to a unit of HIGHER rank (a smaller level number). This is
  # what lets a GM report to a CEO or to a VP within the same company, while
  # preventing a manager from being made the parent of a deputy.
  def parent_must_outrank_child
    return if parent.nil? || level.blank? || parent.level.blank?
    return if parent.level < level

    errors.add(:parent_id, I18n.t("org_structure.errors.parent_rank"))
  end
end
