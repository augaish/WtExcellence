require "roo"

# Loads authorities from the filled-in template into the matrix version given.
#
#   result = AuthorityImportService.import(file: uploaded_file, matrix: matrix)
#   result.categories / result.authorities / result.errors  # => [{ row:, message: }]
#
# A category is found by name in either language and created when new. An
# authority is found by wording inside the matrix and created when new; its
# holders are added where the sheet names them and existing ones are kept.
# Nothing is written unless the whole sheet is valid — one transaction.
class AuthorityImportService
  Result = Struct.new(:categories, :authorities, :errors, keyword_init: true) do
    def success? = errors.empty?
  end

  def self.import(file:, matrix:)
    new(file: file, matrix: matrix).import
  end

  def initialize(file:, matrix:)
    @file = file
    @matrix = matrix
    @company = matrix.company
    @template = AuthorityImportTemplate.new(@company)
    @errors = []
    @categories = 0
    @authorities = 0
  end

  def import
    rows = read_rows
    return failure if @errors.any?
    return fail_with(0, I18n.t("doa.import.empty")) if rows.empty?

    ActiveRecord::Base.transaction do
      rows.each { |row| import_row(row) }
      raise ActiveRecord::Rollback if @errors.any?
    end

    @errors.any? ? failure : Result.new(categories: @categories, authorities: @authorities, errors: [])
  end

  private

  def failure
    Result.new(categories: 0, authorities: 0, errors: @errors)
  end

  def fail_with(row, message)
    @errors << { row: row, message: message }
    failure
  end

  # The header is matched by key in either language, so a company may keep
  # the sheet in Arabic.
  def read_rows
    sheet = Roo::Spreadsheet.open(@file.path, extension: extension)
    sheet = sheet.sheet("Authorities") if sheet.respond_to?(:sheets) && sheet.sheets.include?("Authorities")
    header = sheet.row(1).map { |cell| header_key(cell) }
    rows = []
    (2..sheet.last_row.to_i).each do |i|
      values = sheet.row(i)
      next if values.all? { |v| v.to_s.strip.empty? }

      rows << { number: i, data: header.zip(values).to_h }
    end
    rows
  rescue => e
    @errors << { row: 0, message: I18n.t("doa.import.unreadable", error: e.message) }
    []
  end

  def header_key(cell)
    text = cell.to_s.strip.downcase
    AuthorityImportTemplate::HEADERS.find do |key|
      key == text || I18n.available_locales.any? { |l| I18n.t("doa.import.columns.#{key}", locale: l).downcase == text }
    end || text
  end

  def extension
    ext = File.extname(@file.original_filename.to_s).delete(".").downcase
    ext.presence&.to_sym || :xlsx
  end

  def import_row(row)
    d = row[:data]
    name_en = d["authority_en"].to_s.strip.presence
    name_ar = d["authority_ar"].to_s.strip.presence
    return @errors << { row: row[:number], message: I18n.t("doa.errors.authority_name_required") } if name_en.nil? && name_ar.nil?

    category = find_or_create_category(d["category"], row[:number])
    return if category.nil? && d["category"].to_s.strip.present?

    authority = find_or_create_authority(name_en, name_ar, category, row[:number])
    return if authority.nil?

    AuthorityLevel::KEYS.each do |level|
      d[level].to_s.split(AuthorityImportTemplate::SEPARATOR.strip).map(&:strip).compact_blank.each do |label|
        add_holder(authority, level, label, row[:number])
      end
    end
  end

  def find_or_create_category(name, row_number)
    name = name.to_s.strip
    return nil if name.blank?

    @category_cache ||= {}
    @category_cache[name.downcase] ||= begin
      found = @company.authority_categories.detect { |c| [ c.name_en, c.name_ar ].compact.any? { |n| n.casecmp?(name) } }
      found || create_category(name, row_number)
    end
  end

  def create_category(name, row_number)
    category = @company.authority_categories.new(name.match?(/\p{Arabic}/) ? { name_ar: name } : { name_en: name })
    if category.save
      @categories += 1
      category
    else
      @errors << { row: row_number, message: category.errors.full_messages.join(", ") }
      nil
    end
  end

  def find_or_create_authority(name_en, name_ar, category, row_number)
    existing = @matrix.authorities.detect do |a|
      (name_en && a.name_en.to_s.casecmp?(name_en)) || (name_ar && a.name_ar.to_s.casecmp?(name_ar))
    end
    return existing if existing

    authority = @company.authorities.new(matrix: @matrix, name_en: name_en, name_ar: name_ar, authority_category: category,
      number: @matrix.authorities.maximum(:number).to_i + 1)
    authority.sort_order = authority.number
    if authority.save
      @authorities += 1
      @matrix.authorities.reset
      authority
    else
      @errors << { row: row_number, message: authority.errors.full_messages.join(", ") }
      nil
    end
  end

  # A label from the dropdown ("Unit: Finance", "Person: Sara", "Role: The
  # owning unit"); a bare name is tried against units, then people.
  def add_holder(authority, level, label, row_number)
    attributes = resolve_holder(label)
    return @errors << { row: row_number, message: I18n.t("doa.import.holder_unknown", label: label) } if attributes.nil?

    band = authority.default_band
    return if band.assignments.any? { |a| a.level == level && attributes.all? { |k, v| a.public_send(k) == v } }

    assignment = band.assignments.new(attributes.merge(level: level))
    @errors << { row: row_number, message: assignment.errors.full_messages.join(", ") } unless assignment.save
  end

  def resolve_holder(label)
    kind, name = split_label(label)
    unit = kind.in?([ nil, :unit ]) && @company.org_units.detect { |u| [ u.name_en, u.name_ar, u.code ].compact.any? { |n| n.casecmp?(name) } }
    return { org_unit_id: unit.id } if unit

    person = kind.in?([ nil, :person ]) && @company.users.detect { |u| u.name.to_s.casecmp?(name) || u.email.to_s.casecmp?(name) }
    return { user_id: person.id } if person

    role = kind.in?([ nil, :role ]) && DynamicRole::KEYS.detect do |key|
      key == name.downcase || I18n.available_locales.any? { |l| DynamicRole.label(key, l).casecmp?(name) }
    end
    role ? { dynamic_role: role } : nil
  end

  def split_label(label)
    head, tail = label.split(":", 2).map(&:strip)
    return [ nil, label.strip ] if tail.blank?

    kind = %i[unit person role].detect do |k|
      I18n.available_locales.any? { |l| I18n.t("doa.import.prefixes.#{k}", locale: l).casecmp?(head) }
    end
    kind ? [ kind, tail ] : [ nil, label.strip ]
  end
end
