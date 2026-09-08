# A term a document prints in its التعريفات والاختصارات table.
class PpRecordTerm < ApplicationRecord
  belongs_to :pp_record, class_name: "PpRecord"
  belongs_to :glossary_term

  validates :glossary_term_id, uniqueness: { scope: :pp_record_id }
  validate :term_must_be_same_company

  scope :ordered, -> { order(:sort_order) }

  private

  # A document must not print another company's definitions.
  def term_must_be_same_company
    return if pp_record.nil? || glossary_term.nil?
    return if pp_record.company_id == glossary_term.company_id

    errors.add(:glossary_term, I18n.t("glossary.errors.other_company"))
  end
end
