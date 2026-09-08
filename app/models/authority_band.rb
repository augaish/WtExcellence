# A threshold band of an authority.
#
# The source matrix repeats a whole row — and its twenty role cells — once per
# money bracket, so one change has to be made four times consistently. One
# authority with N bands removes that class of drift entirely.
class AuthorityBand < ApplicationRecord
  belongs_to :authority

  has_many :assignments, -> { ordered }, class_name: "AuthorityAssignment",
    foreign_key: "authority_band_id", dependent: :destroy

  validates :min_amount, :max_amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :max_must_exceed_min
  validate :must_not_overlap_sibling_bands
  validate :matrix_must_be_editable

  # A band with no minimum is the lowest band. PostgreSQL sorts NULL last on an
  # ascending order, which put "up to 10,000" after "above 10,000".
  scope :ordered, -> { order(:sort_order, Arel.sql("min_amount ASC NULLS FIRST"), :created_at) }

  def bounded?
    min_amount.present? || max_amount.present?
  end

  # "Up to SAR 3m", "Above SAR 3m and up to SAR 6m" — the label the matrix
  # prints. A company may write its own; otherwise one is derived so a band is
  # never nameless.
  def display_label(locale = I18n.locale)
    primary, fallback = locale.to_s == "ar" ? [ label_ar, label_en ] : [ label_en, label_ar ]
    written = primary.presence || fallback.presence
    return written if written

    derived_label(locale)
  end

  # Whether an amount falls in this band. Bands are inclusive of their lower
  # bound and exclusive of their upper, so adjacent bands cannot both claim the
  # boundary value.
  def covers?(amount)
    return true unless bounded?
    return false if min_amount.present? && amount < min_amount
    return false if max_amount.present? && amount >= max_amount

    true
  end

  def authorizers
    assignments.select { |assignment| assignment.level == AuthorityLevel::FINAL_KEY }
  end

  def single_authorizer?
    authorizers.size == 1
  end

  def segregation_breaches
    assignments.group_by(&:holder_key).filter_map do |holder_key, held|
      next if holder_key.blank?

      holder_key if AuthorityLevel.segregation_conflict?(held.map(&:level))
    end
  end

  private

  def derived_label(locale)
    return I18n.t("doa.bands.unbounded", locale: locale) if !bounded?
    return I18n.t("doa.bands.up_to", locale: locale, max: format_amount(max_amount)) if min_amount.blank?
    return I18n.t("doa.bands.above", locale: locale, min: format_amount(min_amount)) if max_amount.blank?

    I18n.t("doa.bands.between", locale: locale, min: format_amount(min_amount), max: format_amount(max_amount))
  end

  def format_amount(amount)
    ActiveSupport::NumberHelper.number_to_delimited(amount.to_i)
  end

  def max_must_exceed_min
    return if min_amount.blank? || max_amount.blank? || max_amount > min_amount

    errors.add(:max_amount, I18n.t("doa.errors.max_below_min"))
  end

  # Two bands of one authority claiming the same amount means the matrix cannot
  # say who decides it — the ambiguity the banded rows were meant to remove.
  def must_not_overlap_sibling_bands
    return if authority_id.blank? || !bounded?

    # Read the siblings from the database rather than the association, which may
    # hold copies loaded before a sibling's bounds were changed.
    siblings = AuthorityBand.where(authority_id: authority_id)
    siblings = siblings.where.not(id: id) if persisted?
    return unless siblings.any? { |sibling| overlaps?(sibling) }

    errors.add(:base, I18n.t("doa.errors.bands_overlap"))
  end

  def overlaps?(other)
    return true unless other.bounded?

    lower = [ min_amount || 0, other.min_amount || 0 ].max
    upper = [ max_amount, other.max_amount ].compact.min

    upper.nil? || lower < upper
  end

  def published_matrix_for_guard
    authority&.matrix
  end

  # A matrix that has been published is a statement of record. Changing an
  # authority in it would change what was approved without anyone approving
  # the change; the next version is where edits belong.
  def matrix_must_be_editable
    m = published_matrix_for_guard
    return if m.nil? || !m.completed?

    errors.add(:base, I18n.t("doa.errors.matrix_published"))
  end
end
