require "test_helper"

# Review 03, phase 8: the chart carries what its search and folding need, the
# authority pickers are built lazily, a closed risk shows its closure, and the
# evidence picker names documents.
class Dashboard::Review3Phase8Test < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!
    @company = Company.create!(name: "P8 #{SecureRandom.hex(4)}", license_seats: 10, credits: 50, is_active: true)
    @admin = User.create!(email: "p8-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: "Admin", is_active: true)
    CompanyUser.create!(company: @company, user: @admin, role: CompanyUser::ROLES[:company_admin])
    sign_in @admin
  end

  test "chart nodes carry parent and search text, lines carry their child, and the page offers fit, search and folding" do
    root = @company.org_units.create!(name_en: "Minister", level: 1, code: "01")
    child = @company.org_units.create!(name_en: "Finance Department", level: 2, parent: root)

    get dashboard_org_units_chart_path
    assert_response :success
    assert_select "g.org-chart-node[data-unit-id=?][data-parent-id=?][data-search-text=?]", child.id, root.id, "finance department"
    assert_select "path[data-child-id=?]", child.id
    assert_select "input[type=search][data-action='input->org-chart#search']"
    assert_select "button[data-action='click->org-chart#fit']"
    assert_select "button[data-action='click->org-chart#collapseToTop']"
  end

  test "authority holder pickers are plain selects until Assign is opened" do
    matrix = @company.pp_records.create!(record_type: "executive_doa", title_en: "DoA")
    @company.authorities.create!(matrix: matrix, name_en: "Sign", authority_category: @company.authority_categories.create!(name_en: "Cat"))

    get dashboard_authorities_path
    assert_response :success
    assert_select "details[data-controller=lazy-choices]", minimum: 6
    assert_select "details[data-controller=lazy-choices] [data-controller=choices-select]", count: 0
  end

  test "a closed risk shows its closure without opening Edit" do
    risk = Risk.create!(company: @company, title: "Supplier failure", likelihood: 3, impact: 3)
    risk.update!(status: "closed", closure_reason: "Supplier replaced and verified")

    get dashboard_risk_management_path(risk)
    assert_response :success
    assert_select "body", text: /Supplier replaced and verified/
    assert_select "body", text: /#{Regexp.escape(I18n.t('risk.closure_title'))}/
  end

  test "the evidence picker names documents with their folder, and an attachment opens" do
    folder = @company.folders.create!(name: "QA3", color: "#5C3984")
    upload = Upload.new(company_id: @company.id, folder: folder, filename: "QA-test-document.txt", name: "Supplier audit report",
      mime_type: "text/plain", size_bytes: 5, uploaded_by: @admin.id, visibility: "private")
    upload.file.attach(io: StringIO.new("hello"), filename: "QA-test-document.txt", content_type: "text/plain")
    upload.save!
    record = @company.pp_records.create!(record_type: "policy", title_en: "Policy")

    get dashboard_pp_record_path(record)
    assert_select "select[name='upload_ids[]'] option", text: /Supplier audit report \(QA3\) · QA-test-document.txt/

    record.evidence_attachments.create!(upload: upload, attached_by: @admin.id)
    get dashboard_pp_record_path(record)
    assert_select "a[target=_blank]", text: "Supplier audit report"
  end
end
