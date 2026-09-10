require "caxlsx"

# The Activity page as a sheet: one row per entry, the changes written out.
class ActivityExport
  def initialize(entries, view)
    @entries = entries
    @view = view
  end

  def to_xlsx
    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: "Activity") do |sheet|
      sheet.add_row %w[when who module record_type action record changes].map { |k| I18n.t("activity.columns.#{k}") },
        style: package.workbook.styles.add_style(b: true)
      @entries.each do |entry|
        sheet.add_row [
          I18n.l(entry.created_at, format: :long),
          entry.actor_user&.name,
          I18n.t("activity.modules.#{ActivityCatalogue.module_for(entry.entity_type)}"),
          @view.activity_entity_label(entry.entity_type),
          @view.activity_entry_label(entry),
          entry.payload_json&.dig("label"),
          @view.activity_change_sentences(entry).join("; ")
        ]
      end
      sheet.column_widths 22, 24, 16, 20, 30, 40, 80
    end
    package.to_stream.read
  end
end
