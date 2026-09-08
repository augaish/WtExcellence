require "test_helper"

# Reproduces the P1/P2 defects reported in the 8 September 2026 platform review.
# Each test names the finding it covers so a regression points straight back at
# the report.
class ReviewFindingsTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!

    @company = Company.create!(name: "Review Co #{SecureRandom.hex(4)}", license_seats: 10, credits: 50, is_active: true)
    @admin = User.create!(email: "review-admin-#{SecureRandom.hex(4)}@example.com",
      password: "password123", password_confirmation: "password123", name: "Review Admin", is_active: true)
    CompanyUser.create!(company: @company, user: @admin, role: CompanyUser::ROLES[:company_admin])

    @folder = Folder.create!(company: @company, name: "QA Folder", created_by: @admin.id)
    @upload = Upload.new(company: @company, folder: @folder, name: "QA Document",
      uploaded_by: @admin.id, visibility: "public", filename: "qa.txt",
      mime_type: "text/plain", size_bytes: 12)
    @upload.file.attach(io: StringIO.new("QA evidence"), filename: "qa.txt", content_type: "text/plain")
    @upload.save!
    @record = @company.pp_records.create!(record_type: "policy", title_en: "QA Policy", code: "POL-QA",
      current_stage: "s1_verify", stage_entered_at: Time.current)
    EvidenceAttachment.create!(upload: @upload, attachable: @record, attached_by: @admin.id)
  end

  # F01
  test "All Uploaded Documents listing loads" do
    sign_in @admin
    get folder_path("all")
    assert_response :success
  end

  # F02
  test "company profile loads for a company admin" do
    sign_in @admin
    get dashboard_account_management_company_path(@company)
    assert_response :success
  end

  # F06
  test "evidence reuse heading is a string, not a translation object" do
    sign_in @admin
    get library_path
    assert_response :success
    assert_no_match(/upload_title/, response.body)
  end

  # F03 — the mobile menu was a hand-maintained duplicate that omitted
  # Governance, P&P and Org Structure, and ignored module entitlements.
  test "every permitted desktop destination is reachable from the mobile menu" do
    sign_in @admin
    get dashboard_overview_path
    assert_response :success

    [ dashboard_pp_records_path, dashboard_documenter_path, dashboard_org_units_path,
      dashboard_risk_management_index_path, dashboard_vendors_path ].each do |path|
      assert_select "#mobileMenuPanel a[href=?]", path
    end
  end

  # F03 — a disabled module must disappear from both menus, not just the sidebar.
  test "a disabled module is absent from the mobile menu" do
    @company.set_module!(:pp, false)
    sign_in @admin
    get dashboard_overview_path

    assert_response :success
    assert_select "#mobileMenuPanel a[href=?]", dashboard_pp_records_path, count: 0
    assert_select "#sidebar a[href=?]", dashboard_pp_records_path, count: 0
  end

  # F04 — uploading from inside a folder defaulted to no folder at all.
  test "the upload dialog defaults to the folder being viewed" do
    sign_in @admin
    get folder_path(@folder)

    assert_response :success
    assert_select "select[name=?] option[selected][value=?]", "upload[folder_id]", @folder.id
  end

  # F05 — Edit was a placeholder alert; uploads#update already existed.
  test "document metadata can be edited from the detail page" do
    sign_in @admin
    get folder_uploads_upload_path(folder_id: @folder.id, id: @upload.id)
    assert_response :success
    assert_select "#edit_document_dialog"
    assert_no_match(/to be implemented/, response.body)

    patch folder_uploads_upload_path(folder_id: @folder.id, id: @upload.id),
      params: { upload: { name: "Renamed Document", notes: "Corrected notes" } }

    assert_redirected_to folder_uploads_upload_path(folder_id: @folder.id, id: @upload.id)
    assert_equal "Renamed Document", @upload.reload.name
    assert_equal "Corrected notes", @upload.notes
  end

  # F07
  test "a record link appears on the document detail page" do
    sign_in @admin
    get folder_uploads_upload_path(folder_id: @folder.id, id: @upload.id)
    assert_response :success
    assert_includes response.body, "QA Policy"
  end
end
