require "test_helper"

class Dashboard::RecordDocumentRenderTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!

    @company = Company.create!(name: "Render Co #{SecureRandom.hex(4)}", license_seats: 10, credits: 50, is_active: true)
    @admin = User.create!(email: "render-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: "Render Admin", is_active: true)
    CompanyUser.create!(company: @company, user: @admin, role: CompanyUser::ROLES[:company_admin])

    @unit = @company.org_units.create!(name_en: "Institutional Excellence", name_ar: "التميز المؤسسي", level: 1)
    @process = @company.pp_processes.create!(name_en: "Policy development", level: 2, category: "core", parent: @company.pp_processes.create!(name_en: "L1 " + "Policy development", level: 1, category: "core"),
      objective: "Govern how policies are written")
    @record = @company.pp_records.create!(record_type: "procedure", title_en: "Policy Development Procedure",
      title_ar: "إجراء تطوير السياسات", code: "PRO-01", pp_process: @process, owner_org_unit: @unit,
      version_label: "v1.0", classification: "secret")
  end

  test "the document renders with its cover, contents and sections" do
    @process.steps.create!(position: 1, activity: "Draft the policy", responsible_title: "Policies Specialist",
      duration_value: 3, duration_unit: "days")

    sign_in @admin
    get document_dashboard_pp_record_path(@record)

    assert_response :success
    assert_select "h1", text: "Policy Development Procedure"
    assert_select "h2", text: I18n.t("record_document.contents")
    assert_select "table td", text: "Draft the policy"
    assert_includes response.body, "PRO-01"
  end

  test "the cover shows the document's classification" do
    sign_in @admin
    get document_dashboard_pp_record_path(@record)

    assert_includes response.body, DocumentClassification.label("secret")
  end

  test "the company logo is printed beside the platform logo" do
    @company.brand_logo.attach(io: StringIO.new("logo"), filename: "logo.png", content_type: "image/png")

    sign_in @admin
    get document_dashboard_pp_record_path(@record)

    assert_select "img[alt=?]", @company.name
    assert_select "img[alt=?]", "Way to Excellence"
  end

  test "a readable brand colour is applied to the document" do
    @company.update!(brand_primary_color: "#0B4F6C")

    sign_in @admin
    get document_dashboard_pp_record_path(@record)

    assert_includes response.body, "#0B4F6C"
  end

  test "an unreadable brand colour does not reach the document" do
    @company.update!(brand_primary_color: "#FFFF00")

    sign_in @admin
    get document_dashboard_pp_record_path(@record)

    assert_not_includes response.body, "#FFFF00"
    assert_includes response.body, BrandPalette::DEFAULT_PRIMARY
  end

  test "the document renders right to left in Arabic" do
    sign_in @admin
    get document_dashboard_pp_record_path(@record, locale: "ar")

    assert_response :success
    assert_select "html[dir=?]", "rtl"
    assert_select "h1", text: "إجراء تطوير السياسات"
  end

  test "the authority matrix prints its conditions rather than an asterisk" do
    authority = @process.authorities.create!(item: "Publication", decision: "Approve publication")
    authority.assignments.create!(level: "authorize", holder_title: "Deputy Minister", condition: "Above SAR 1m")

    sign_in @admin
    get document_dashboard_pp_record_path(@record)

    assert_includes response.body, "Deputy Minister"
    assert_includes response.body, "Above SAR 1m"
  end

  test "a record from another company is not reachable" do
    other = Company.create!(name: "Other #{SecureRandom.hex(4)}", license_seats: 5, credits: 1, is_active: true)
    foreign = other.pp_records.create!(record_type: "policy", title_en: "Foreign policy")

    sign_in @admin
    get document_dashboard_pp_record_path(foreign)

    assert_response :redirect
  end
end
