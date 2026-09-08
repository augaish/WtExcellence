# A row of the المراجع table. Free text is enough for an external regulation,
# but pointing at an ingested clause records exactly which requirement the
# document answers — and keeps the reference in step when the clause changes.
class PpRecordReference < ApplicationRecord
  belongs_to :pp_record, class_name: "PpRecord"
  belongs_to :clause, optional: true

  validates :name, length: { maximum: 300 }
  validates :source, length: { maximum: 300 }
  validate :must_name_something

  scope :ordered, -> { order(:sort_order, :created_at) }
  scope :to_clauses, -> { where.not(clause_id: nil) }

  # The clause's own title wins over typed text, so a renamed clause does not
  # leave a stale reference behind.
  def display_name(locale = I18n.locale)
    clause_title(locale).presence || name.to_s
  end

  def display_source(locale = I18n.locale)
    return source.to_s if clause.nil?

    standard = clause.standard_version&.standard
    standard&.display_name(locale.to_s).presence || source.to_s
  end

  private

  def clause_title(locale)
    return "" if clause.nil?

    [ clause.full_code, clause.title(locale.to_s) ].compact_blank.join(" — ")
  end

  def must_name_something
    return if clause_id.present? || name.present?

    errors.add(:name, I18n.t("pp_records.errors.reference_needs_name"))
  end
end
