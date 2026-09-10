require "caxlsx"

# The workbook a company fills in to load its executive matrix at once.
#
# Sheet "Authorities": one row per authority — its category, its wording in
# both languages, and one column per level. Each level cell is a dropdown of
# the company's organizational units, people and dynamic roles, so a holder
# is picked, never typed. Sheet "Lists" holds those choices, units and people
# in their own columns. Sheet "How to fill" explains the rest.
class AuthorityImportTemplate
  HOLDER_COLUMNS = AuthorityLevel::KEYS.freeze
  HEADERS = (%w[category authority_en authority_ar] + HOLDER_COLUMNS).freeze
  SEPARATOR = " | ".freeze

  def initialize(company, locale: I18n.locale)
    @company = company
    @locale = locale
  end

  def to_xlsx
    package = Axlsx::Package.new
    workbook = package.workbook
    add_authorities_sheet(workbook)
    add_lists_sheet(workbook)
    add_help_sheet(workbook)
    package.to_stream.read
  end

  # Labels as they appear in the dropdowns: a prefix says what kind of holder
  # it is, so "Finance" the unit is never confused with a person of that name.
  def unit_labels
    @company.org_units.active.ordered.map { |unit| "#{prefix(:unit)}: #{unit.display_name(@locale)}" }
  end

  def people_labels
    @company.users.order(:name).map { |user| "#{prefix(:person)}: #{user.name}" }
  end

  def role_labels
    DynamicRole::KEYS.map { |key| "#{prefix(:role)}: #{DynamicRole.label(key, @locale)}" }
  end

  def prefix(kind)
    I18n.t("doa.import.prefixes.#{kind}", locale: @locale)
  end

  private

  def add_authorities_sheet(workbook)
    header = workbook.styles.add_style(b: true, bg_color: "F7F7FD", border: { style: :thin, color: "E3E3E3" })
    workbook.add_worksheet(name: "Authorities") do |sheet|
      sheet.add_row HEADERS.map { |key| I18n.t("doa.import.columns.#{key}", locale: @locale) }, style: header
      sheet.add_row example_row
      sheet.column_widths 26, 44, 44, 22, 22, 22, 22, 22, 22

      # Rows 2..1000 of each level column pick from the combined list.
      HOLDER_COLUMNS.each_with_index do |_, i|
        column = (("A".ord + 3 + i).chr)
        sheet.add_data_validation("#{column}2:#{column}1000",
          type: :list, formula1: "'Lists'!$C$2:$C$#{holder_list_size + 1}",
          showErrorMessage: false, hideDropDown: false)
      end
    end
  end

  def add_lists_sheet(workbook)
    workbook.add_worksheet(name: "Lists") do |sheet|
      sheet.add_row [ I18n.t("doa.picker.units", locale: @locale), I18n.t("doa.picker.people", locale: @locale),
                      I18n.t("doa.import.columns.holders", locale: @locale) ]
      units, people, all = unit_labels, people_labels, holder_list
      all.each_with_index { |label, i| sheet.add_row [ units[i], people[i], label ] }
      sheet.column_widths 36, 36, 40
    end
  end

  def add_help_sheet(workbook)
    workbook.add_worksheet(name: "How to fill") do |sheet|
      I18n.t("doa.import.help", locale: @locale).each { |line| sheet.add_row [ line ] }
      sheet.column_widths 110
    end
  end

  def holder_list
    unit_labels + people_labels + role_labels
  end

  def holder_list_size
    [ holder_list.size, 1 ].max
  end

  def example_row
    first_unit = unit_labels.first
    [ I18n.t("doa.import.example.category", locale: @locale), "Approve purchase orders up to SAR 100,000",
      "اعتماد أوامر الشراء حتى 100,000 ريال", first_unit, nil, nil, nil, first_unit, nil ]
  end
end
