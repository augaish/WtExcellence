require "test_helper"

class Dashboard::RecordDocxDownloadTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!

    @company = Company.create!(name: "Dl Co #{SecureRandom.hex(4)}", license_seats: 10, credits: 50, is_active: true)
    @admin = User.create!(email: "dl-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: "Dl Admin", is_active: true)
    CompanyUser.create!(company: @company, user: @admin, role: CompanyUser::ROLES[:company_admin])
    @record = @company.pp_records.create!(record_type: "policy", title_en: "Data Governance Policy",
      code: "POL-01", description: "Policy clauses.")
  end

  test "the document downloads as a Word file" do
    sign_in @admin
    get document_docx_dashboard_pp_record_path(@record)

    assert_response :success
    assert_equal "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
      response.media_type
    assert_match(/attachment/, response.headers["Content-Disposition"])
    assert_match(/POL-01/, response.headers["Content-Disposition"])
  end

  test "what downloads is a real archive Word could open" do
    sign_in @admin
    get document_docx_dashboard_pp_record_path(@record)

    names = Zip::File.open_buffer(StringIO.new(response.body)).entries.map(&:name)
    assert_includes names, "word/document.xml"
  end

  test "the Word button is offered on the document page" do
    sign_in @admin
    get document_dashboard_pp_record_path(@record)

    assert_response :success
    assert_select "a[href=?]", document_docx_dashboard_pp_record_path(@record, locale: I18n.locale)
  end

  test "another company's document cannot be downloaded" do
    other = Company.create!(name: "Other #{SecureRandom.hex(4)}", license_seats: 5, credits: 1, is_active: true)
    foreign = other.pp_records.create!(record_type: "policy", title_en: "Foreign policy")

    sign_in @admin
    get document_docx_dashboard_pp_record_path(foreign)

    assert_response :redirect
  end
end
