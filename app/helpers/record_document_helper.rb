module RecordDocumentHelper
  # Which columns each table section prints, in order. Kept beside the renderer
  # rather than in the assembler, because this is a presentation choice: the
  # assembler decides what a section contains, this decides how it is laid out.
  TABLE_COLUMNS = {
    "definitions" => %i[term abbreviation definition],
    "steps" => %i[position activity description responsible duration system],
    "service_levels" => %i[service metric target measurement coverage],
    "references" => %i[name source],
    "classification" => %i[classification definition],
    "change_log" => %i[version date prepared_by change],
    "approvals" => %i[role unit name date status]
  }.freeze

  # Column keys map to i18n column names; a few differ from the row's own key.
  CELL_KEYS = {
    position: :position,
    classification: :label,
    definition: :definition,
    change: :description
  }.freeze

  def document_columns_for(section)
    TABLE_COLUMNS.fetch(section.key, section.payload.first&.keys || [])
  end

  def document_cell(row, column)
    return document_approval_status(row) if column == :status

    value = row[CELL_KEYS.fetch(column, column)]
    return l(value, format: :long) if value.is_a?(Date) || value.is_a?(Time)

    value
  end

  private

  def document_approval_status(row)
    t(row[:received] ? "record_document.approval_received" : "record_document.approval_pending")
  end
end
