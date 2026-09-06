require "test_helper"

class PpProcessImportServiceTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "PImport #{SecureRandom.hex(4)}", license_seats: 5, is_active: true)
  end

  def csv_upload(content)
    file = Tempfile.new([ "processes", ".csv" ])
    file.write(content)
    file.rewind
    ActionDispatch::Http::UploadedFile.new(
      tempfile: file, filename: "processes.csv", type: "text/csv"
    )
  end

  test "imports levels 1 and 2 with the card fields" do
    csv = <<~CSV
      code,name_en,name_ar,level,parent_code,category,objective,owner_unit_code,owner_email,trigger,inputs,outputs,frequency,total_time_value,total_time_unit,automation_status,related_policies,technical_systems,forms_used,kpis
      P-01,Governance,الحوكمة,1,,management,Govern,,,Board decision,Agenda,Policies,annual,5,days,partially_automated,Gov policy,GRC,Minutes,On-time %
      P-01-01,Policy Mgmt,إدارة السياسات,2,P-01,,Manage policies,,,Request,Draft,Published,on_demand,30,days,manual,,,,
    CSV

    result = PpProcessImportService.import(file: csv_upload(csv), company: @company)

    assert result.success?, result.errors.inspect
    assert_equal 2, result.created

    root = @company.pp_processes.find_by(code: "P-01")
    child = @company.pp_processes.find_by(code: "P-01-01")
    assert_equal "management", root.category
    assert_equal "Board decision", root.trigger_text
    assert_equal root.id, child.parent_id
    assert_equal 2, child.level
    assert_equal "management", child.effective_category
  end

  test "links the owning org unit by code" do
    unit = @company.org_units.create!(name_en: "Quality", level: 1, code: "01")
    csv = "code,name_en,level,parent_code,owner_unit_code\nP-01,Gov,1,,01\n"

    result = PpProcessImportService.import(file: csv_upload(csv), company: @company)

    assert result.success?, result.errors.inspect
    assert_equal unit.id, @company.pp_processes.find_by(code: "P-01").owner_org_unit_id
  end

  test "ignores enum values that are not recognised" do
    csv = "code,name_en,level,parent_code,frequency,automation_status\nP-01,Gov,1,,fortnightly,magic\n"

    result = PpProcessImportService.import(file: csv_upload(csv), company: @company)

    assert result.success?, result.errors.inspect
    process = @company.pp_processes.find_by(code: "P-01")
    assert_nil process.frequency
    assert_nil process.automation_status
  end

  test "saves nothing when a parent code is missing" do
    csv = "code,name_en,level,parent_code\nP-01-01,Child,2,P-99\n"

    result = PpProcessImportService.import(file: csv_upload(csv), company: @company)

    refute result.success?
    assert_equal 0, @company.pp_processes.count
  end

  test "the template lists every supported header" do
    assert_equal PpProcessImportService::HEADERS, PpProcessImportService.template_csv.lines.first.strip.split(",")
  end
end
