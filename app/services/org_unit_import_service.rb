require "roo"

# Bulk-import org units from an .xlsx/.csv sheet.
#
#   result = OrgUnitImportService.import(file: uploaded_file, company: company)
#   result.created / result.updated / result.errors  # => [{ row:, message: }]
#
# Rows are matched on `code` (upsert). Parents are linked in a SECOND pass so a
# child may appear before its parent in the sheet. Nothing is written unless the
# whole sheet is valid — the import runs in one transaction.
class OrgUnitImportService
  HEADERS = %w[
    code name_en name_ar level parent_code group head_email cost_center email mandates
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
      csv << [ "01", "Executive Office", "المكتب التنفيذي", 1, "", "Leadership", "", "CC-100", "exec@example.com", "Set strategy | Approve policies" ]
      csv << [ "01-01", "Quality Department", "إدارة الجودة", 2, "01", "Support", "", "CC-110", "quality@example.com", "Own the QMS" ]
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
    @errors << { row: 0, message: I18n.t("org_structure.import.unreadable", error: e.message) }
    []
  end

  def extension
    ext = File.extname(@file.original_filename.to_s).delete(".").downcase
    ext.presence&.to_sym || :xlsx
  end

  # Create/update every unit without touching parents.
  def pass_one(rows)
    rows.each do |row|
      d = row[:data]
      code = d["code"].to_s.strip
      if code.blank?
        @errors << { row: row[:number], message: I18n.t("org_structure.import.code_required") }
        next
      end

      unit = @company.org_units.find_or_initialize_by(code: code)
      new_record = unit.new_record?

      unit.name_en = d["name_en"].to_s.strip.presence
      unit.name_ar = d["name_ar"].to_s.strip.presence
      unit.level = d["level"].presence ? d["level"].to_i : 1
      unit.cost_center = d["cost_center"].to_s.strip.presence
      unit.email = d["email"].to_s.strip.presence
      unit.mandate_list = d["mandates"].to_s.split("|")
      unit.org_group = find_or_create_group(d["group"])
      unit.head_user = find_head(d["head_email"])

      if unit.save
        new_record ? @created += 1 : @updated += 1
      else
        @errors << { row: row[:number], message: unit.errors.full_messages.join(", ") }
      end
    end
  end

  # Link parents now that every code exists.
  def pass_two(rows)
    rows.each do |row|
      d = row[:data]
      code = d["code"].to_s.strip
      parent_code = d["parent_code"].to_s.strip
      next if code.blank? || parent_code.blank?

      unit = @company.org_units.find_by(code: code)
      parent = @company.org_units.find_by(code: parent_code)
      next if unit.nil?

      if parent.nil?
        @errors << { row: row[:number], message: I18n.t("org_structure.import.parent_missing", code: parent_code) }
        next
      end

      unit.parent = parent
      unless unit.save
        @errors << { row: row[:number], message: unit.errors.full_messages.join(", ") }
      end
    end
  end

  def find_or_create_group(name)
    name = name.to_s.strip
    return nil if name.blank?

    @group_cache ||= {}
    @group_cache[name] ||= @company.org_groups.detect { |g| [ g.name_en, g.name_ar ].compact.any? { |n| n.casecmp?(name) } } ||
      @company.org_groups.create!(name_en: name, color: "#5C3984", sort_order: @company.org_groups.size)
  end

  def find_head(email)
    email = email.to_s.strip
    return nil if email.blank?

    User.find_by(email: email)
  end
end
