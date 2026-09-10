require "caxlsx"

# The workbook a super admin fills in to invite a company's users at once.
#
# Sheet "Users": one row per person — name, email, company role and the
# organizational unit they belong to. Role and unit are dropdowns. The sheet
# carries exactly as many empty rows as the company has free licence seats,
# and says so in its first line. Sheet "How to fill" explains the rest.
class UserImportTemplate
  HEADERS = %w[name email role org_unit].freeze

  def initialize(company, locale: I18n.locale)
    @company = company
    @locale = locale
  end

  def free_seats
    [ @company.license_seats.to_i - @company.company_users.count, 0 ].max
  end

  def to_xlsx
    package = Axlsx::Package.new
    workbook = package.workbook
    add_users_sheet(workbook)
    add_lists_sheet(workbook)
    add_help_sheet(workbook)
    package.to_stream.read
  end

  def role_labels
    CompanyUser::ROLES.values.map { |role| role_label(role) }
  end

  def role_label(role)
    I18n.t("user_import.roles.#{role}", locale: @locale)
  end

  def unit_labels
    @company.org_units.active.ordered.map { |unit| unit.display_name(@locale) }
  end

  private

  def add_users_sheet(workbook)
    header = workbook.styles.add_style(b: true, bg_color: "F7F7FD", border: { style: :thin, color: "E3E3E3" })
    note = workbook.styles.add_style(i: true, fg_color: "797C81")
    workbook.add_worksheet(name: "Users") do |sheet|
      sheet.add_row [ I18n.t("user_import.seats_line", free: free_seats, total: @company.license_seats.to_i, locale: @locale) ], style: note
      sheet.add_row HEADERS.map { |key| I18n.t("user_import.columns.#{key}", locale: @locale) }, style: header
      free_seats.times { |i| sheet.add_row [ nil, nil, nil, nil ] }
      sheet.column_widths 30, 36, 28, 30

      last = free_seats + 2
      sheet.add_data_validation("C3:C#{[ last, 3 ].max}", type: :list, formula1: "'Lists'!$A$2:$A$#{role_labels.size + 1}",
        showErrorMessage: true, hideDropDown: false)
      if unit_labels.any?
        sheet.add_data_validation("D3:D#{[ last, 3 ].max}", type: :list, formula1: "'Lists'!$B$2:$B$#{unit_labels.size + 1}",
          showErrorMessage: false, hideDropDown: false)
      end
    end
  end

  def add_lists_sheet(workbook)
    workbook.add_worksheet(name: "Lists") do |sheet|
      sheet.add_row [ I18n.t("user_import.columns.role", locale: @locale), I18n.t("user_import.columns.org_unit", locale: @locale) ]
      roles, units = role_labels, unit_labels
      [ roles.size, units.size ].max.times { |i| sheet.add_row [ roles[i], units[i] ] }
      sheet.column_widths 28, 36
    end
  end

  def add_help_sheet(workbook)
    workbook.add_worksheet(name: "How to fill") do |sheet|
      I18n.t("user_import.help", locale: @locale).each { |line| sheet.add_row [ line ] }
      sheet.column_widths 110
    end
  end
end
