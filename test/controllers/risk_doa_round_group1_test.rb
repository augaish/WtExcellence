require "test_helper"

# Risk/DoA test round, group 1.
class RiskDoaRoundGroup1Test < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!
    @company = Company.create!(name: "R1 Co #{SecureRandom.hex(4)}", license_seats: 10, credits: 10, is_active: true)
    @admin = person("admin", :company_admin)
    @qm = person("qm", :company_quality_manager)
    @unit = @company.org_units.create!(name_en: "Finance", level: 1)
    @matrix = AuthorityMatrixVersionService.first_version(@company, actor: @admin)
    @finance = @company.authority_categories.create!(name_en: "Financial")
    @hr = @company.authority_categories.create!(name_en: "HR")
  end

  def person(prefix, role)
    user = User.create!(email: "#{prefix}-#{SecureRandom.hex(4)}@example.com", password: "Password1234",
      password_confirmation: "Password1234", name: prefix.humanize, is_active: true)
    CompanyUser.create!(company: @company, user: user, role: CompanyUser::ROLES[role])
    user
  end

  def sheet(rows)
    file = Tempfile.new([ "authorities", ".xlsx" ])
    Axlsx::Package.new do |p|
      p.workbook.add_worksheet(name: "Authorities") do |s|
        s.add_row AuthorityImportTemplate::HEADERS
        rows.each { |r| s.add_row r }
      end
      p.serialize(file.path)
    end
    Rack::Test::UploadedFile.new(file.path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
  end

  test "the quality manager reads Governance and Authorities but cannot change them" do
    sign_in @qm
    get dashboard_risk_management_index_path
    assert_response :success
    get dashboard_authorities_path
    assert_response :success
    assert_select "form[action=?]", dashboard_create_authority_path(matrix_id: @matrix.id), 0
    post "/dashboard/risk_management", params: { risk: { title: "No", cause: "c", event: "e", impact_statement: "i", likelihood: 2, impact: 2 } }
    assert_not Risk.exists?(title: "No")
  end

  test "an empty category is a drop area, and several authorities are deleted at once" do
    a = @company.authorities.create!(matrix: @matrix, authority_category: @finance, name_en: "Pay invoices")
    b = @company.authorities.create!(matrix: @matrix, authority_category: @finance, name_en: "Sign contracts")
    c = @company.authorities.create!(matrix: @matrix, authority_category: @finance, name_en: "Hire staff")
    sign_in @admin
    get dashboard_authorities_path
    assert_select "section[data-category-id=?] [data-authority-matrix-target=rows] [data-empty]", @hr.id, text: I18n.t("doa.category_empty_drop")
    assert_select "input[type=checkbox][form=bulk-delete-authorities]", 3

    delete dashboard_destroy_authorities_path(matrix_id: @matrix.id), params: { ids: [ a.id, b.id ] }
    assert_equal [ c.id ], @matrix.authorities.reload.pluck(:id)
    assert_equal I18n.t("doa.bulk.deleted", count: 2), flash[:notice]
  end

  test "re-importing updates the wording, category and holders of existing authorities and reports it" do
    existing = @company.authorities.create!(matrix: @matrix, authority_category: @finance, name_en: "Pay invoices")
    existing.default_band.assignments.create!(level: "authorize", org_unit: @unit)
    same = @company.authorities.create!(matrix: @matrix, authority_category: @finance, name_en: "Sign contracts")
    same.default_band.assignments.create!(level: "authorize", org_unit: @unit)

    sign_in @admin
    post dashboard_import_authorities_path(matrix_id: @matrix.id), params: { file: sheet([
      [ "HR", "Pay invoices", "صرف الفواتير", nil, nil, nil, nil, "Person: #{@admin.name}", nil ],
      [ "Financial", "Sign contracts", nil, nil, nil, nil, nil, "Unit: Finance", nil ],
      [ "Financial", "New power", nil, nil, nil, nil, nil, "Unit: Finance", nil ]
    ]) }
    assert_redirected_to dashboard_authorities_path(matrix_id: @matrix.id)
    assert_equal I18n.t("doa.import.done", categories: 0, authorities: 1, updated: 1, unchanged: 1), flash[:notice]

    existing.reload
    assert_equal [ "صرف الفواتير", @hr ], [ existing.name_ar, existing.authority_category ]
    assert_equal [ [ "authorize", @admin.id ] ], existing.default_band.assignments.map { |x| [ x.level, x.user_id ] }
    assert_equal 1, @matrix.authorities.where(name_en: "New power").sole.default_band.assignments.count
  end

  test "the matrix prints one category or all, grouped under numbered headings" do
    @company.authorities.create!(matrix: @matrix, authority_category: @finance, name_en: "Pay invoices", sort_order: 1)
    @company.authorities.create!(matrix: @matrix, authority_category: @hr, name_en: "Hire staff", sort_order: 1)

    all = RecordDocument.new(@matrix, locale: :en).sections.find { |s| s.key == "executive_matrix" }
    assert_equal [ "Financial", "HR" ], all.payload.map { |r| r[:category] }
    only_hr = RecordDocument.new(@matrix, locale: :en, category_id: @hr.id).sections.find { |s| s.key == "executive_matrix" }
    assert_equal [ "Hire staff" ], only_hr.payload.map { |r| r[:authority] }
    assert_equal "#{@hr.number}.1", only_hr.payload.sole[:number], "the matrix number is kept"

    sign_in @admin
    get dashboard_authorities_path
    assert_select "form[action=?] select[name=category_id] option", dashboard_authority_matrix_pdf_path, 3
    get document_dashboard_pp_record_path(@matrix)
    assert_select "h3", text: /Financial/
    assert_select "h3", text: /HR/
    assert_equal "#{@hr.number} · HR", "#{@hr.number} · #{@hr.display_name}"
    pdf = RecordPdfRenderer.new(@matrix, locale: :en, category: @hr)
    assert_match(/HR-en\.pdf\z/, pdf.filename)
  end
end
