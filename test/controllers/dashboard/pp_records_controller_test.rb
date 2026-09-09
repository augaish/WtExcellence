require "test_helper"

class Dashboard::PpRecordsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!

    @company = Company.create!(name: "RecCtl #{SecureRandom.hex(4)}", license_seats: 10, credits: 50, is_active: true)

    @admin = User.create!(email: "rec-admin-#{SecureRandom.hex(4)}@example.com",
      password: "password123", password_confirmation: "password123", name: "Admin", is_active: true)
    CompanyUser.create!(company: @company, user: @admin, role: CompanyUser::ROLES[:company_admin])

    @viewer = User.create!(email: "rec-viewer-#{SecureRandom.hex(4)}@example.com",
      password: "password123", password_confirmation: "password123", name: "Viewer", is_active: true)
    CompanyUser.create!(company: @company, user: @viewer, role: CompanyUser::ROLES[:company_viewer])

    @record = @company.pp_records.create!(record_type: "policy", title_en: "Data Policy", code: "POL-01")
  end

  test "index lists records with the type tabs" do
    sign_in @admin
    get dashboard_pp_records_path

    assert_response :success
    assert_select "body", text: /Data Policy/
    assert_select "a[href=?]", dashboard_pp_records_path(record_type: "procedure")
    assert_select "a[href=?]", dashboard_pp_packages_path
  end

  test "the add button names the open tab and Packages sits beside it" do
    sign_in @admin
    get dashboard_pp_records_path(record_type: "policy")

    assert_response :success
    assert_select "a[href=?]", new_dashboard_pp_record_path(record_type: "policy"), text: "Add Policy"
    assert_select "a[href=?]", dashboard_pp_packages_path, text: I18n.t("pp_records.packages.title")

    get dashboard_pp_records_path
    assert_select "a[href=?]", new_dashboard_pp_record_path, text: I18n.t("pp_records.add_record")
  end

  test "the type tab filters the list" do
    sign_in @admin
    @company.pp_records.create!(record_type: "form", title_en: "Request Form")

    get dashboard_pp_records_path(record_type: "form")

    assert_response :success
    assert_select "body", text: /Request Form/
  end

  test "a viewer can read but gets no manage actions" do
    sign_in @viewer
    get dashboard_pp_records_path

    assert_response :success
    assert_select "a[href=?]", new_dashboard_pp_record_path(record_type: nil), count: 0
  end

  test "admin creates a record" do
    sign_in @admin

    assert_difference -> { @company.pp_records.count }, 1 do
      post dashboard_pp_records_path, params: {
        pp_record: { record_type: "procedure", title_en: "Onboarding", title_ar: "التعيين",
                     version_label: "v1.0", effective_date: "2026-01-01", review_date: "2027-01-01" }
      }
    end

    record = @company.pp_records.find_by(title_en: "Onboarding")
    assert_equal "procedure", record.record_type
    assert_equal "v1.0", record.version_label
  end

  test "the new form suggests a code prefixed by type" do
    sign_in @admin
    get new_dashboard_pp_record_path(record_type: "form")

    assert_response :success
    assert_select "input[name='pp_record[code]'][value=?]", "FRM-01"
  end

  test "a record cannot set its own package" do
    sign_in @admin
    package = @company.pp_packages.create!(name: "Package A")

    patch dashboard_pp_record_path(@record), params: {
      pp_record: { title_en: "Data Policy", package_id: package.id }
    }

    assert_nil @record.reload.package_id, "package_id must not be assignable from the record form"
  end

  test "a viewer cannot create a record" do
    sign_in @viewer

    assert_no_difference -> { @company.pp_records.count } do
      post dashboard_pp_records_path, params: { pp_record: { record_type: "policy", title_en: "Sneaky" } }
    end
  end

  test "show displays the package as read-only information" do
    sign_in @admin
    package = @company.pp_packages.create!(name: "Q1 Cycle")
    @record.update!(package: package)

    get dashboard_pp_record_path(@record)

    assert_response :success
    assert_select "body", text: /Q1 Cycle/
    assert_includes response.body, I18n.t("pp_records.packages.read_only_hint")
  end

  test "show says unpackaged when the record has no package" do
    sign_in @admin
    get dashboard_pp_record_path(@record)

    assert_response :success
    assert_includes response.body, I18n.t("pp_records.packages.unpackaged")
  end

  test "attaching an existing library file links it" do
    sign_in @admin
    upload = create_upload

    assert_difference -> { @record.evidence_attachments.count }, 1 do
      post attach_documents_dashboard_pp_record_path(@record), params: { upload_ids: [ upload.id ] }
    end

    assert_includes @record.reload.uploads.map(&:id), upload.id
  end

  test "attaching the same file twice does not duplicate it" do
    sign_in @admin
    upload = create_upload
    post attach_documents_dashboard_pp_record_path(@record), params: { upload_ids: [ upload.id ] }

    assert_no_difference -> { @record.evidence_attachments.count } do
      post attach_documents_dashboard_pp_record_path(@record), params: { upload_ids: [ upload.id ] }
    end
  end

  test "detaching a document removes the link but keeps the file" do
    sign_in @admin
    upload = create_upload
    post attach_documents_dashboard_pp_record_path(@record), params: { upload_ids: [ upload.id ] }

    delete detach_document_dashboard_pp_record_path(@record, upload_id: upload.id)

    assert_equal 0, @record.reload.evidence_attachments.count
    assert Upload.exists?(upload.id), "the Library file must survive"
  end

  test "the edit form renders" do
    sign_in @admin
    get edit_dashboard_pp_record_path(@record)
    assert_response :success
  end

  test "a record from another company is not reachable" do
    sign_in @admin
    other = Company.create!(name: "Other #{SecureRandom.hex(4)}", license_seats: 1, is_active: true)
    foreign = other.pp_records.create!(record_type: "policy", title_en: "Foreign")

    get dashboard_pp_record_path(foreign)

    assert_redirected_to dashboard_pp_records_path
  end

  private

  def create_upload
    upload = Upload.new(
      company_id: @company.id, filename: "policy.pdf", name: "policy.pdf",
      mime_type: "application/pdf", size_bytes: 1234, uploaded_by: @admin.id, visibility: "private"
    )
    upload.file.attach(
      io: StringIO.new("%PDF-1.4 test"), filename: "policy.pdf", content_type: "application/pdf"
    )
    upload.save!
    upload
  end
end
