require "caxlsx"

# The workbook a company fills in to load its organizational structure.
# Sheet "Units": one row per unit. The code column is text, so 01/02 stays
# 01/02; level, group and parent code are dropdowns. Sheet "Lists" holds the
# choices; sheet "How to fill" explains the rest.
class OrgUnitImportTemplate
  def initialize(company, locale: I18n.locale)
    @company = company
    @locale = locale
  end

  def to_xlsx
    package = Axlsx::Package.new
    wb = package.workbook
    text = wb.styles.add_style(num_fmt: 49)
    header = wb.styles.add_style(b: true, bg_color: "F7F7FD", border: { style: :thin, color: "E3E3E3" })
    headers = OrgUnitImportService::HEADERS
    codes = @company.org_units.active.ordered.map(&:code).compact_blank
    groups = @company.org_groups.ordered.map(&:display_name)
    heads = @company.users.order(:name).map(&:email)

    wb.add_worksheet(name: "Units") do |sheet|
      sheet.add_row headers.map { |key| I18n.t("org_structure.import.columns.#{key}", locale: @locale, default: key) }, style: header
      sheet.add_row [ "01", "Executive Office", "المكتب التنفيذي", 1, nil, groups.first, heads.first, "CC-100", "exec@example.com", "Set strategy | Approve policies" ], style: [ text ] + [ nil ] * 9
      sheet.add_row [ "01/01", "Quality Department", "إدارة الجودة", 2, "01", groups.first, nil, "CC-110", "quality@example.com", "Own the QMS" ], style: [ text ] + [ nil ] * 9
      (3..300).each { |r| sheet.add_row [ nil ] * headers.size, style: [ text ] + [ nil ] * 9 }
      sheet.column_widths 14, 34, 34, 8, 14, 22, 30, 12, 30, 50
      sheet.add_data_validation("D2:D300", type: :whole, operator: :between, formula1: "1", formula2: OrgLevelDefinition::MAX_LEVEL.to_s, showErrorMessage: true)
      sheet.add_data_validation("E2:E300", type: :list, formula1: "'Lists'!$A$2:$A$#{[ codes.size, 1 ].max + 1}", showErrorMessage: false, hideDropDown: false) if codes.any?
      sheet.add_data_validation("F2:F300", type: :list, formula1: "'Lists'!$B$2:$B$#{[ groups.size, 1 ].max + 1}", showErrorMessage: false, hideDropDown: false) if groups.any?
      sheet.add_data_validation("G2:G300", type: :list, formula1: "'Lists'!$C$2:$C$#{[ heads.size, 1 ].max + 1}", showErrorMessage: false, hideDropDown: false) if heads.any?
    end

    wb.add_worksheet(name: "Lists") do |sheet|
      sheet.add_row [ I18n.t("org_structure.import.columns.parent_code", locale: @locale, default: "parent_code"),
                      I18n.t("org_structure.import.columns.group", locale: @locale, default: "group"),
                      I18n.t("org_structure.import.columns.head_email", locale: @locale, default: "head_email") ]
      [ codes.size, groups.size, heads.size ].max.times { |i| sheet.add_row [ codes[i], groups[i], heads[i] ], style: [ text, nil, nil ] }
      sheet.column_widths 16, 24, 32
    end

    wb.add_worksheet(name: "How to fill") do |sheet|
      Array(I18n.t("org_structure.import.help", locale: @locale)).each { |line| sheet.add_row [ line ] }
      sheet.column_widths 110
    end

    package.to_stream.read
  end
end
