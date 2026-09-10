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

  test "admin creates a policy and the system assigns its code" do
    sign_in @admin
    hr = @company.org_units.create!(name_en: "Human Resources", level: 1, code: "HR")

    assert_difference -> { @company.pp_records.count }, 1 do
      post dashboard_pp_records_path, params: {
        pp_record: { record_type: "policy", title_en: "Onboarding", title_ar: "التعيين", scope: "All staff",
                     owner_org_unit_id: hr.id, effective_date: "2026-01-01", review_date: "2027-01-01" }
      }
    end

    record = @company.pp_records.find_by(title_en: "Onboarding")
    assert_equal "policy", record.record_type
    assert_equal "POL-HR-001-V1", record.code
    assert_equal "All staff", record.scope
  end

  test "a procedure is filed under a level-2 process and carries the architecture number" do
    sign_in @admin
    hr = @company.org_units.create!(name_en: "Human Resources", level: 1, code: "HR")
    l1 = @company.pp_processes.create!(name_en: "Human capital", level: 1, category: "support")
    l2 = @company.pp_processes.create!(name_en: "Recruiting", level: 2, parent: l1)
    policy = @company.pp_records.create!(record_type: "policy", title_en: "HR Policy", owner_org_unit: hr)

    post dashboard_pp_records_path, params: {
      pp_record: { record_type: "procedure", title_en: "Hire a candidate", owner_org_unit_id: hr.id, pp_process_id: l2.id,
                   trigger_text: "Vacancy approved", frequency: "on_demand", automation_status: "manual" },
      related_policy_ids: [ policy.id ]
    }

    record = @company.pp_records.find_by(title_en: "Hire a candidate")
    assert_equal "PROC-HR-3.1.1.1-V1", record.code
    assert_equal "3.1.1.1", record.architecture_number
    assert_equal [ policy ], record.related_policies.to_a
  end

  test "a procedure without a level-2 process is refused" do
    sign_in @admin
    l1 = @company.pp_processes.create!(name_en: "Human capital", level: 1, category: "support")

    post dashboard_pp_records_path, params: { pp_record: { record_type: "procedure", title_en: "Loose", pp_process_id: l1.id } }
    assert_response :unprocessable_entity
    assert_nil @company.pp_records.find_by(title_en: "Loose")
  end

  test "the new form fixes the type from the tab and shows the code as assigned on save" do
    sign_in @admin
    get new_dashboard_pp_record_path(record_type: "form")

    assert_response :success
    assert_select "input[type=hidden][name='pp_record[record_type]'][value=form]"
    assert_select "select[name='pp_record[record_type]']", count: 0
    assert_select "body", text: /#{Regexp.escape(I18n.t('pp_records.code_on_save'))}/
  end

  test "a service keeps its participating units" do
    sign_in @admin
    it = @company.org_units.create!(name_en: "IT", level: 1, code: "IT")
    legal = @company.org_units.create!(name_en: "Legal", level: 1, code: "LG")

    post dashboard_pp_records_path, params: {
      pp_record: { record_type: "service", title_en: "Laptop request", service_type: "internal", owner_org_unit_id: it.id,
                   requirements: "Manager approval", delivery_period: "3 days" },
      participating_unit_ids: [ legal.id ]
    }

    record = @company.pp_records.find_by(title_en: "Laptop request")
    assert_equal "SEV-IT-001-V1", record.code
    assert_equal [ legal ], record.participating_units.to_a
  end

  test "the tabs are the journey types, and the authority matrices are not among them" do
    sign_in @admin
    get dashboard_pp_records_path
    PpRecord::TAB_TYPES.each { |type| assert_select "a[href=?]", dashboard_pp_records_path(record_type: type) }
    assert_select "a[href=?]", dashboard_pp_records_path(record_type: "executive_doa"), count: 0
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

  test "deleting a policy that an authority names as its basis clears the link instead of failing" do
    sign_in @admin
    matrix = @company.pp_records.create!(record_type: "executive_doa", title_en: "DoA")
    authority = @company.authorities.create!(matrix: matrix, name_en: "Sign contracts", basis_record: @record)

    delete dashboard_pp_record_path(@record)

    assert_redirected_to dashboard_pp_records_path
    refute PpRecord.exists?(@record.id)
    assert_nil authority.reload.basis_record_id
  end
end
