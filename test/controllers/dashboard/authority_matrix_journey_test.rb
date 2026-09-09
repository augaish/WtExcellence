require "test_helper"

# R01/R02 and the simplified matrix journey: group, authority, six boxes.
class Dashboard::AuthorityMatrixJourneyTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!

    @company = Company.create!(name: "Journey Co #{SecureRandom.hex(4)}", license_seats: 10, credits: 50, is_active: true)
    @admin = User.create!(email: "journey-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: "Journey Admin", is_active: true)
    CompanyUser.create!(company: @company, user: @admin, role: CompanyUser::ROLES[:company_admin])
    @colleague = User.create!(email: "colleague-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: "Finance Director", is_active: true)
    CompanyUser.create!(company: @company, user: @colleague, role: CompanyUser::ROLES[:company_viewer])

    @matrix = @company.pp_records.create!(record_type: "executive_doa", title_en: "Executive DoA")
    @procurement = @company.org_units.create!(name_en: "Procurement", level: 1)
    sign_in @admin
  end

  def m; { matrix_id: @matrix.id }; end

  test "an empty category is shown with a place to add its first authority" do
    post dashboard_create_authority_category_path, params: m.merge(authority_category: { name_en: "Procurement thresholds" })
    follow_redirect!

    assert_includes response.body, "Procurement thresholds"
    assert_includes response.body, I18n.t("doa.category_empty")
    assert_select "form[action=?]", dashboard_create_authority_path(m)
  end



  test "each authority shows six boxes and a holder can be a unit or a person" do
    authority = @company.authorities.create!(matrix: @matrix, name_en: "Approve purchase orders")

    post dashboard_create_authority_assignment_path(authority_id: authority.id), params: m.merge(holder: "unit:#{@procurement.id}",
      authority_assignment: { level: "prepare" })
    post dashboard_create_authority_assignment_path(authority_id: authority.id), params: m.merge(holder: "user:#{@colleague.id}",
      authority_assignment: { level: "authorize" })

    assignments = authority.reload.assignments
    assert_equal @procurement, assignments.find_by(level: "prepare").org_unit
    assert_equal @colleague, assignments.find_by(level: "authorize").user

    get dashboard_authorities_path(m)
    AuthorityLevel::KEYS.each { |level| assert_includes response.body, AuthorityLevel.label(level) }
    assert_includes response.body, "Finance Director"
    assert_includes response.body, I18n.t("doa.picker.people")
  end

  test "a person from another company cannot be named as a holder" do
    other = Company.create!(name: "Other #{SecureRandom.hex(4)}", license_seats: 5, credits: 1, is_active: true)
    stranger = User.create!(email: "stranger-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: "Stranger", is_active: true)
    CompanyUser.create!(company: other, user: stranger, role: CompanyUser::ROLES[:company_viewer])
    authority = @company.authorities.create!(matrix: @matrix, name_en: "X")

    post dashboard_create_authority_assignment_path(authority_id: authority.id), params: m.merge(holder: "user:#{stranger.id}",
      authority_assignment: { level: "authorize" })

    assert_equal 0, authority.reload.assignments.count
  end

  test "a category and an authority can be renamed without losing their relationships" do
    category = @company.authority_categories.create!(name_en: "Contracting")
    authority = @company.authorities.create!(matrix: @matrix, name_en: "Sign contracts", authority_category: category)
    authority.bands.sole.assignments.create!(level: "authorize", org_unit: @procurement)

    patch dashboard_update_authority_category_path(category), params: m.merge(authority_category: { name_en: "Contracting & procurement" })
    patch dashboard_update_authority_path(authority), params: m.merge(authority: { name_en: "Sign and amend contracts" })

    assert_equal "Contracting & procurement", category.reload.name_en
    assert_equal "Sign and amend contracts", authority.reload.name_en
    assert_equal 1, authority.assignments.count, "renaming must not disturb holders"
  end

  test "removing a category keeps its authorities" do
    category = @company.authority_categories.create!(name_en: "Temporary")
    authority = @company.authorities.create!(matrix: @matrix, name_en: "Kept", authority_category: category)

    delete dashboard_destroy_authority_category_path(category), params: m

    assert Authority.exists?(authority.id)
    assert_nil authority.reload.authority_category_id
  end


  test "an empty matrix does not claim every authority is in order" do
    get dashboard_authorities_path(m)

    assert_not_includes response.body, I18n.t("doa.findings.none")
  end
end
