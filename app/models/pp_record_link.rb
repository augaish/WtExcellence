# A typed link from one record to another: the policies a procedure implements,
# the forms it uses. Rows rather than free text, so a renamed policy stays
# correct in every procedure that names it.
class PpRecordLink < ApplicationRecord
  KINDS = %w[related_policy form_used].freeze

  belongs_to :pp_record, class_name: "PpRecord"
  belongs_to :linked_record, class_name: "PpRecord"

  validates :kind, inclusion: { in: KINDS }
  validates :linked_record_id, uniqueness: { scope: [ :pp_record_id, :kind ] }
  validate :same_company

  scope :of_kind, ->(kind) { where(kind: kind) }

  private

  def same_company
    return if pp_record.nil? || linked_record.nil? || pp_record.company_id == linked_record.company_id

    errors.add(:linked_record_id, I18n.t("pp_records.errors.link_other_company"))
  end
end
