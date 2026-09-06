require "test_helper"

class OrgUnitImportServiceTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Import Co #{SecureRandom.hex(4)}", license_seats: 5, is_active: true)
  end

  def csv_upload(content)
    file = Tempfile.new([ "org_units", ".csv" ])
    file.write(content)
    file.rewind
    ActionDispatch::Http::UploadedFile.new(
      tempfile: file, filename: "org_units.csv", type: "text/csv"
    )
  end

  test "imports a hierarchy and links parents" do
    csv = <<~CSV
      code,name_en,name_ar,level,parent_code,group,head_email,cost_center,email,mandates
      01,CEO,الرئيس,1,,Leadership,,CC-1,ceo@example.com,Set strategy | Approve policies
      01-01,Quality,الجودة,2,01,Support,,CC-2,q@example.com,Own the QMS
    CSV

    result = OrgUnitImportService.import(file: csv_upload(csv), company: @company)

    assert result.success?, result.errors.inspect
    assert_equal 2, result.created

    ceo = @company.org_units.find_by(code: "01")
    quality = @company.org_units.find_by(code: "01-01")
    assert_equal ceo.id, quality.parent_id
    assert_equal [ "Set strategy", "Approve policies" ], ceo.mandate_list
    assert_equal "Leadership", ceo.org_group.name_en
  end

  # A child listed before its parent must still link, which is why the import
  # runs in two passes.
  test "links a parent that appears later in the sheet" do
    csv = <<~CSV
      code,name_en,level,parent_code
      01-01,Quality,2,01
      01,CEO,1,
    CSV

    result = OrgUnitImportService.import(file: csv_upload(csv), company: @company)

    assert result.success?, result.errors.inspect
    assert_equal @company.org_units.find_by(code: "01").id,
                 @company.org_units.find_by(code: "01-01").parent_id
  end

  test "updates an existing unit instead of duplicating it" do
    @company.org_units.create!(code: "01", name_en: "Old name", level: 1)

    csv = "code,name_en,level,parent_code\n01,New name,1,\n"
    result = OrgUnitImportService.import(file: csv_upload(csv), company: @company)

    assert result.success?, result.errors.inspect
    assert_equal 1, result.updated
    assert_equal 1, @company.org_units.count
    assert_equal "New name", @company.org_units.find_by(code: "01").name_en
  end

  test "saves nothing when any row is invalid" do
    csv = <<~CSV
      code,name_en,level,parent_code
      01,CEO,1,
      02,,1,
    CSV

    result = OrgUnitImportService.import(file: csv_upload(csv), company: @company)

    refute result.success?
    assert_equal 0, @company.org_units.count, "a failed import must roll back completely"
  end

  test "reports a missing parent code with the row number" do
    csv = "code,name_en,level,parent_code\n01-01,Quality,2,99\n"
    result = OrgUnitImportService.import(file: csv_upload(csv), company: @company)

    refute result.success?
    assert_equal 2, result.errors.first[:row]
    assert_includes result.errors.first[:message], "99"
  end

  test "rejects a row without a code" do
    csv = "code,name_en,level,parent_code\n,No code,1,\n"
    result = OrgUnitImportService.import(file: csv_upload(csv), company: @company)

    refute result.success?
    assert_equal 0, @company.org_units.count
  end

  test "the template lists every supported header" do
    assert_equal OrgUnitImportService::HEADERS, OrgUnitImportService.template_csv.lines.first.strip.split(",")
  end
end
