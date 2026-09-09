require "roo"

# Bulk-import the process architecture from an .xlsx/.csv sheet.
# Same two-pass, all-or-nothing approach as OrgUnitImportService.
class PpProcessImportService
  HEADERS = %w[
    code name_en name_ar level parent_code category objective owner_unit_code owner_email
    trigger inputs outputs frequency total_time_value total_time_unit automation_status
    related_policies technical_systems forms_used kpis
  ].freeze

  Result = Struct.new(:created, :updated, :errors, keyword_init: true) do
    def success? = errors.empty?
    def total = created + updated
  end

  def self.import(file:, company:)
    new(file: file, company: company).import
  end

  def self.template_csv
    require "csv"
    CSV.generate do |csv|
      csv << HEADERS
      csv << [ "P-01", "Corporate Governance", "الحوكمة المؤسسية", 1, "", "management", "Govern the organisation", "01", "",
               "Board decision", "Board agenda", "Approved policies", "annual", 5, "days", "partially_automated",
               "Governance Policy", "GRC system", "Board minutes form", "% policies approved on time" ]
      csv << [ "P-01-01", "Policy Management", "إدارة السياسات", 2, "P-01", "", "Manage the policy lifecycle", "01-01", "",
               "New policy request", "Draft policy", "Published policy", "on_demand", 30, "days", "manual",
               "", "", "", "" ]
    end
  end

  def initialize(file:, company:)
    @file = file
    @company = company
    @errors = []
    @created = 0
    @updated = 0
  end

  def import
    rows = read_rows
    return Result.new(created: 0, updated: 0, errors: @errors) if @errors.any?

    ActiveRecord::Base.transaction do
      pass_one(rows)
      raise ActiveRecord::Rollback if @errors.any?

      pass_two(rows)
      raise ActiveRecord::Rollback if @errors.any?
    end

    if @errors.any?
      Result.new(created: 0, updated: 0, errors: @errors)
    else
      Result.new(created: @created, updated: @updated, errors: [])
    end
  end

  private

  def read_rows
    sheet = Roo::Spreadsheet.open(@file.path, extension: extension)
    header = sheet.row(1).map { |h| h.to_s.strip.downcase }
    rows = []
    (2..sheet.last_row.to_i).each do |i|
      values = sheet.row(i)
      next if values.all? { |v| v.to_s.strip.empty? }

      rows << { number: i, data: header.zip(values).to_h }
    end
    rows
  rescue => e
    @errors << { row: 0, message: I18n.t("process_architecture.import.unreadable", error: e.message) }
    []
  end

  def extension
    ext = File.extname(@file.original_filename.to_s).delete(".").downcase
    ext.presence&.to_sym || :xlsx
  end

  # Level 1 rows first so a level-2 child can attach in pass two even if the
  # sheet lists it earlier.
  def pass_one(rows)
    rows.sort_by { |r| r[:data]["level"].to_i }.each do |row|
      d = row[:data]
      code = d["code"].to_s.strip
      if code.blank?
        @errors << { row: row[:number], message: I18n.t("process_architecture.import.code_required") }
        next
      end

      process = @company.pp_processes.find_or_initialize_by(code: code)
      new_record = process.new_record?

      process.name_en = d["name_en"].to_s.strip.presence
      process.name_ar = d["name_ar"].to_s.strip.presence
      process.category = normalize(d["category"], PpProcess::CATEGORIES)
      process.objective = d["objective"].to_s.strip.presence
      process.trigger_text = d["trigger"].to_s.strip.presence
      process.inputs = d["inputs"].to_s.strip.presence
      process.outputs = d["outputs"].to_s.strip.presence
      process.frequency = normalize(d["frequency"], PpProcess::FREQUENCIES)
      process.total_time_value = d["total_time_value"].presence
      process.total_time_unit = normalize(d["total_time_unit"], PpProcess::TIME_UNITS)
      process.automation_status = normalize(d["automation_status"], PpProcess::AUTOMATION_STATUSES)
      process.related_policies = d["related_policies"].to_s.strip.presence
      process.technical_systems = d["technical_systems"].to_s.strip.presence
      process.forms_used = d["forms_used"].to_s.strip.presence
      process.kpis = d["kpis"].to_s.strip.presence
      process.owner_org_unit = @company.org_units.find_by(code: d["owner_unit_code"].to_s.strip.presence)
      process.owner_user = User.find_by(email: d["owner_email"].to_s.strip.presence)

      # Level 1 rows validate immediately; deeper rows get their level in pass
      # two once the parent exists (level must be parent.level + 1).
      level = d["level"].presence ? d["level"].to_i : 1
      process.level = level
      process.parent = nil if level == 1

      if level == 1
        if process.save
          new_record ? @created += 1 : @updated += 1
        else
          @errors << { row: row[:number], message: process.errors.full_messages.join(", ") }
        end
      else
        # Defer: remember it, save in pass two with the parent attached.
        (@deferred ||= []) << { row: row[:number], process: process, parent_code: d["parent_code"].to_s.strip, new_record: new_record }
      end
    end
  end

  def pass_two(_rows)
    Array(@deferred).each do |item|
      process = item[:process]
      parent = @company.pp_processes.find_by(code: item[:parent_code])
      if parent.nil?
        @errors << { row: item[:row], message: I18n.t("process_architecture.import.parent_missing", code: item[:parent_code]) }
        next
      end

      if parent.level >= PpProcess::MAX_LEVEL
        @errors << { row: item[:row], message: I18n.t("process_architecture.import.too_deep", code: item[:parent_code]) }
        next
      end

      process.parent = parent
      process.level = parent.level + 1

      if process.save
        item[:new_record] ? @created += 1 : @updated += 1
      else
        @errors << { row: item[:row], message: process.errors.full_messages.join(", ") }
      end
    end
  end

  def normalize(value, allowed)
    v = value.to_s.strip.downcase.tr(" ", "_")
    allowed.include?(v) ? v : nil
  end
end
