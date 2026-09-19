require "test_helper"
require "minitest/mock"

# Test team items 4, 6, 7, 18 and 21.
class Group2FixesTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!
    @company = Company.create!(name: "G2 Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @admin = User.create!(email: "g2-#{SecureRandom.hex(4)}@example.com", password: "Password1234",
      password_confirmation: "Password1234", name: "Admin", is_active: true)
    CompanyUser.create!(company: @company, user: @admin, role: CompanyUser::ROLES[:company_admin])
  end

  test "4: a password needs ten characters with letters and digits, wherever it is set" do
    user = User.new(email: "weak-#{SecureRandom.hex(3)}@example.com", name: "W", password: "abcdefgh", password_confirmation: "abcdefgh")
    assert_not user.valid?
    assert_includes user.errors[:password], PasswordRule.message
    user.password = user.password_confirmation = "abcdefghij"
    assert_not user.valid?, "letters only is refused"
    user.password = user.password_confirmation = "abcdefghi1"
    assert user.valid?

    invited = User.create!(email: "inv-#{SecureRandom.hex(3)}@example.com", name: "I", password: "Temporary123", password_confirmation: "Temporary123",
      invitation_token: User.generate_invitation_token, invitation_sent_at: Time.current, invitation_expires_at: 7.days.from_now, is_active: false)
    CompanyUser.create!(company: @company, user: invited, role: CompanyUser::ROLES[:company_viewer])
    post submit_invitation_path(invited.invitation_token), params: { password: "short1", password_confirmation: "short1" }
    assert_includes response.body, CGI.escapeHTML(PasswordRule.message)
    assert_not invited.reload.is_active
  end

  test "6 and 7: the org template is an Excel workbook whose codes stay text, and a date-looking code imports as typed" do
    sign_in @admin
    get template_dashboard_org_units_path
    assert_response :success
    assert_equal "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", response.media_type
    book = Roo::Excelx.new(StringIO.new(response.body), file_warning: :ignore)
    assert_equal [ "Units", "Lists", "How to fill" ], book.sheets
    assert_equal "01/01", book.sheet("Units").cell(3, 1), "the example code keeps its slash"

    file = Tempfile.new([ "units", ".xlsx" ])
    Axlsx::Package.new do |p|
      p.workbook.add_worksheet(name: "Units") do |sheet|
        sheet.add_row OrgUnitImportService::HEADERS
        sheet.add_row [ "10", "Finance", "المالية", 1, nil, nil, nil, nil, nil, nil ]
        # What Excel does to 10/02 typed in a general cell: a date.
        sheet.add_row [ Date.new(Date.current.year, 10, 2), "Treasury", "الخزينة", 2, "10", nil, nil, nil, nil, nil ]
      end
      p.serialize(file.path)
    end
    post import_dashboard_org_units_path, params: { file: Rack::Test::UploadedFile.new(file.path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet") }
    assert_redirected_to dashboard_org_units_path
    treasury = @company.org_units.find_by(name_en: "Treasury")
    assert treasury, "the second row imported"
    refute_match(/\d{4}-\d{2}-\d{2}/, treasury.code, "the code is not a date")
    assert_equal "10", treasury.parent.code
  end

  test "18: the document is written in the record's chosen language, not the page's" do
    record = @company.pp_records.create!(record_type: "policy", title_en: "Arabic Policy", title_ar: "سياسة", description: "x", language: "ar")
    sign_in @admin
    get document_dashboard_pp_record_path(record)
    assert_select "html[dir=rtl][lang=ar]"

    record.update!(language: "en")
    get document_dashboard_pp_record_path(record, locale: :ar)
    assert_select "html[dir=ltr][lang=en]"

    get edit_dashboard_pp_record_path(record)
    assert_select "select[name='pp_record[language]']"
  end

  test "21: when the PDF engine is missing the matrix download says so instead of silently printing the page" do
    matrix = AuthorityMatrixVersionService.first_version(@company, actor: @admin)
    sign_in @admin
    RecordPdfRenderer.stub(:binary, nil) do
      get dashboard_authority_matrix_pdf_path(matrix_id: matrix.id)
    end
    assert_redirected_to document_dashboard_pp_record_path(matrix)
    assert_equal I18n.t("record_document.pdf_engine_missing"), flash[:alert]
  end
end
