# A term or abbreviation defined once for the company and reused by every
# document that needs it, so the same term cannot drift between documents.
class GlossaryTerm < ApplicationRecord
  belongs_to :company

  has_many :pp_record_terms, dependent: :destroy
  has_many :pp_records, through: :pp_record_terms

  validates :term_en, length: { maximum: 250 }
  validates :term_ar, length: { maximum: 250 }
  validates :abbreviation, length: { maximum: 50 }, allow_blank: true
  validate :must_have_a_term

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:sort_order, :term_en, :term_ar) }

  def display_term(locale = I18n.locale)
    primary, fallback = locale.to_s == "ar" ? [ term_ar, term_en ] : [ term_en, term_ar ]
    primary.presence || fallback.presence || abbreviation.to_s
  end

  def display_definition(locale = I18n.locale)
    primary, fallback = locale.to_s == "ar" ? [ definition_ar, definition_en ] : [ definition_en, definition_ar ]
    primary.presence || fallback.presence || ""
  end

  private

  def must_have_a_term
    return if term_en.present? || term_ar.present?

    errors.add(:base, I18n.t("glossary.errors.term_required"))
  end
end
