require "test_helper"

# Test team clarifications: items 8/10 (import with Arabic headers, three levels),
# 9 (code follows the number), 12 (durations roll up), 13 (KPI rows), 14 (description in the card).
class Group6FixesTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!
    @company = Company.create!(name: "G6 Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @admin = User.create!(email: "g6-#{SecureRandom.hex(4)}@example.com", password: "Password1234",
      password_confirmation: "Password1234", name: "Admin", is_active: true)
    CompanyUser.create!(company: @company, user: @admin, role: CompanyUser::ROLES[:company_admin])
    sign_in @admin
  end

  def procedure_tree
    l1 = @company.pp_processes.create!(name_en: "Ops", level: 1, category: "core")
    l2 = @company.pp_processes.create!(name_en: "Review", level: 2, parent: l1)
    [ l1, l2 ]
  end

  test "8 and 10: a sheet with Arabic headers and three levels imports, codes as text" do
    file = Tempfile.new([ "units", ".xlsx" ])
    Axlsx::Package.new do |p|
      p.workbook.add_worksheet(name: "Units") do |sheet|
        sheet.add_row OrgUnitImportService::HEADERS.map { |k| I18n.t("org_structure.import.columns.#{k}", locale: :ar) }
        sheet.add_row [ "01", "Ministry", "الوزارة", 1, nil, nil, nil, nil, nil, nil ]
        sheet.add_row [ "01-02", "Deputyship", "الوكالة", 2, "01", nil, nil, nil, nil, nil ]
        sheet.add_row [ "01-02-03", "Department", "الإدارة", 3, "01-02", nil, nil, nil, nil, nil ]
      end
      p.serialize(file.path)
    end
    post import_dashboard_org_units_path, params: { file: Rack::Test::UploadedFile.new(file.path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet") }
    assert_redirected_to dashboard_org_units_path
    dept = @company.org_units.find_by(code: "01-02-03")
    assert_equal [ 3, "01-02", "الإدارة" ], [ dept.level, dept.parent.code, dept.name_ar ]
  end

  test "9: renumbering an unpublished procedure updates its code and card everywhere" do
    _l1, l2 = procedure_tree
    procedure = @company.pp_records.create!(record_type: "procedure", title_en: "Proc", pp_process: l2)
    assert_match(/\.1-V1\z/, procedure.code)
    patch dashboard_pp_record_path(procedure), params: { pp_record: { sequence_number: 7 } }
    procedure.reload
    assert_match(/\.7-V1\z/, procedure.code)
    assert_equal "#{l2.architecture_number}.7", procedure.architecture_number
    get dashboard_pp_record_path(procedure)
    assert_includes response.body, procedure.code
  end

  test "12: durations roll up from steps to procedure to level 2 to level 1" do
    l1, l2 = procedure_tree
    a = @company.pp_records.create!(record_type: "procedure", title_en: "A", pp_process: l2)
    a.steps.create!(position: 1, activity: "x", duration_value: 2, duration_unit: "hours")
    a.steps.create!(position: 2, activity: "y", duration_value: 30, duration_unit: "minutes")
    b = @company.pp_records.create!(record_type: "procedure", title_en: "B", pp_process: l2, total_time_value: 1, total_time_unit: "days")

    assert_equal 150, a.duration_minutes
    assert_equal 480, b.duration_minutes
    assert_equal 630, l2.rollup_minutes
    assert_equal 630, l1.rollup_minutes
    assert_equal "1.3 #{I18n.t("process_architecture.time_units.days", locale: :en)}", l1.rollup_label(:en)
    get dashboard_pp_processes_path
    assert_includes response.body, I18n.t("process_architecture.rollup_duration", duration: l1.rollup_label)
  end

  test "13 and 14: KPI rows print as a table and the procedure description sits in its card only" do
    _l1, l2 = procedure_tree
    procedure = @company.pp_records.create!(record_type: "procedure", title_en: "Proc", pp_process: l2, description: "Purpose of it")
    post dashboard_pp_record_kpis_path(procedure), params: { pp_record_kpi: { name_en: "Cycle time", target: "5", unit: "days", measurement_method: "From request to approval", frequency: "monthly" } }
    assert_equal 1, procedure.kpi_rows.count
    get dashboard_pp_record_path(procedure)
    assert_select "#kpis li", 1

    doc = RecordDocument.new(procedure.reload, locale: :en)
    keys = doc.sections.map(&:key)
    assert_includes keys, "kpis"
    assert_not_includes keys, "body", "the description is printed in the card, not as a separate Content section"
    card = doc.sections.find { |s| s.key == "process_card" }
    assert_equal "Purpose of it", card.payload["objective"]
    assert_equal "Cycle time", doc.sections.find { |s| s.key == "kpis" }.payload.first[:name]

    successor = RecordVersionService.new(procedure.tap { |r| r.update!(current_stage: PpStage::TERMINAL_KEYS.first, published_at: Time.current) }, actor: @admin).open_next
    assert_equal 1, successor.kpi_rows.count
  end
end
