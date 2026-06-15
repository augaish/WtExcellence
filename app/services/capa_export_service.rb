class CapaExportService
  require "csv"
  require "zip"

  def initialize(capas, language = "en")
    @capas = capas
    @language = language.to_s
    @language = "en" unless [ "en", "ar" ].include?(@language)
  end

  def generate_zip
    I18n.with_locale(@language.to_sym) do
      Zip::OutputStream.write_buffer do |zip|
        zip.put_next_entry("capas.csv")
        zip.write(capas_csv_with_bom)

        zip.put_next_entry("actions.csv")
        zip.write(actions_csv_with_bom)
      end.string
    end
  end

  def filename
    "capas_export_#{Date.today.strftime('%Y%m%d')}.zip"
  end

  private

  def capas_csv_with_bom
    bom + generate_capas_csv
  end

  def actions_csv_with_bom
    bom + generate_actions_csv
  end

  def generate_capas_csv
    CSV.generate(force_quotes: true) do |csv|
      csv << capa_headers
      @capas.each do |capa|
        csv << build_capa_row(capa)
      end
    end
  end

  def generate_actions_csv
    CSV.generate(force_quotes: true) do |csv|
      csv << action_headers
      @capas.includes(capa_actions: :company_users).each do |capa|
        capa.capa_actions.each do |action|
          csv << build_action_row(capa, action)
        end
      end
    end
  end

  def bom
    "\xEF\xBB\xBF"
  end

  def capa_headers
    headers = [
      I18n.t("capa_export.headers.capa_code", default: I18n.t("capa_code", default: "CAPA Code")),
      I18n.t("capa_export.headers.title", default: I18n.t("title", default: "Title")),
      I18n.t("capa_export.headers.description", default: I18n.t("description", default: "Description")),
      I18n.t("capa_export.headers.status", default: I18n.t("status_label", default: "Status")),
      I18n.t("capa_export.headers.priority", default: I18n.t("priority", default: "Priority")),
      I18n.t("capa_export.headers.source", default: I18n.t("source", default: "Source")),
      I18n.t("capa_export.headers.standard", default: I18n.t("standard", default: "Standard")),
      I18n.t("capa_export.headers.due_date", default: I18n.t("due_date", default: "Due Date")),
      I18n.t("capa_export.headers.assigned_to", default: I18n.t("assigned_to", default: "Assigned To")),
      I18n.t("capa_export.headers.created_at", default: I18n.t("created_at", default: "Created At"))
    ]

    rtl_columns(headers)
  end

  def action_headers
    headers = [
      I18n.t("capa_export.actions.headers.capa_code", default: I18n.t("capa_code", default: "CAPA Code")),
      I18n.t("capa_export.actions.headers.title", default: I18n.t("title", default: "Title")),
      I18n.t("capa_export.actions.headers.action_type", default: I18n.t("action_type", default: "Action Type")),
      I18n.t("capa_export.actions.headers.status", default: I18n.t("status_label", default: "Status")),
      I18n.t("capa_export.actions.headers.due_date", default: I18n.t("due_date", default: "Due Date")),
      I18n.t("capa_export.actions.headers.notes", default: I18n.t("notes", default: "Notes")),
      I18n.t("capa_export.actions.headers.assigned_to", default: I18n.t("assigned_to", default: "Assigned To")),
      I18n.t("capa_export.actions.headers.created_at", default: I18n.t("created_at", default: "Created At"))
    ]

    rtl_columns(headers)
  end

  def build_capa_row(capa)
    row = [
      capa.friendly_code || "",
      translate_text(capa.title),
      translate_text(capa.description),
      translate_status(capa.status),
      translate_priority(capa.priority),
      translate_source(capa.source),
      capa.standard&.display_name(@language) || "",
      capa.due_date&.strftime("%Y-%m-%d") || "",
      capa.users.map { |user| translate_text(user.name) }.join("; "),
      capa.created_at.strftime("%Y-%m-%d %H:%M:%S")
    ]

    rtl_columns(row)
  end

  def build_action_row(capa, action)
    row = [
      capa.friendly_code || "",
      translate_text(action.title),
      translate_action_type(action.action_type),
      translate_action_status(action.status),
      action.due_date&.strftime("%Y-%m-%d") || "",
      translate_text(action.notes),
      action.company_users.map { |company_user| translate_text(company_user.user.name) }.join("; "),
      action.created_at.strftime("%Y-%m-%d %H:%M:%S")
    ]

    rtl_columns(row)
  end

  def translate_status(status)
    case status
    when "open"
      I18n.t("capa_management_ui.statuses.open", default: I18n.t("open", default: "Open"))
    when "assigned"
      I18n.t("capa_management_ui.statuses.assigned", default: I18n.t("assigned", default: "Assigned"))
    when "in_progress"
      I18n.t("capa_management_ui.statuses.in_progress", default: I18n.t("in_progress", default: "In Progress"))
    when "closed"
      I18n.t("capa_management_ui.statuses.closed", default: I18n.t("closed", default: "Closed"))
    else
      status
    end
  end

  def translate_action_status(status)
    case status.to_s.downcase
    when "started"
      I18n.t("capa_actions.statuses.started", default: "Started")
    when "in_progress"
      I18n.t("capa_actions.statuses.in_progress", default: "In Progress")
    when "done"
      I18n.t("capa_actions.statuses.done", default: "Done")
    else
      status
    end
  end

  def translate_action_type(action_type)
    case action_type.to_s.downcase
    when "corrective"
      I18n.t("capa_actions.types.corrective", default: "Corrective")
    when "preventive"
      I18n.t("capa_actions.types.preventive", default: "Preventive")
    else
      action_type
    end
  end

  def translate_priority(priority)
    case priority
    when "low"
      I18n.t("priority_levels.low", default: I18n.t("low", default: "Low"))
    when "medium"
      I18n.t("priority_levels.medium", default: I18n.t("medium", default: "Medium"))
    when "high"
      I18n.t("priority_levels.high", default: I18n.t("high", default: "High"))
    else
      priority
    end
  end

  def translate_source(source)
    return "" if source.blank?

    I18n.t("capa_sources.#{source}", default: source.to_s.humanize)
  end

  def translate_text(text)
    text.to_s
  end

  def rtl?
    @language == "ar"
  end

  def rtl_columns(array)
    rtl? ? array.reverse : array
  end
end
