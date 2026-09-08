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

  test "the first thresholds a user enters bound the authority instead of vanishing" do
    authority = @company.authorities.create!(matrix: @matrix, name_en: "Approve purchase orders")

    post dashboard_create_authority_band_path(authority_id: authority.id), params: m.merge(authority_band: { min_amount: 0, max_amount: 10_000 })
    post dashboard_create_authority_band_path(authority_id: authority.id), params: m.merge(authority_band: { min_amount: 10_000, max_amount: 50_000 })
    post dashboard_create_authority_band_path(authority_id: authority.id), params: m.merge(authority_band: { min_amount: 50_000 })

    bands = authority.reload.bands.ordered
    assert_equal 3, bands.count, "three non-overlapping bands must all survive"
    assert_equal [ [ 0, 10_000 ], [ 10_000, 50_000 ], [ 50_000, nil ] ],
      bands.map { |b| [ b.min_amount&.to_i, b.max_amount&.to_i ] }

    get dashboard_authorities_path(m)
    assert_includes response.body, bands.first.display_label
    assert_includes response.body, bands.last.display_label
  end

  test "an overlapping band is refused with a reason and the others are untouched" do
    authority = @company.authorities.create!(matrix: @matrix, name_en: "Approve purchase orders")
    post dashboard_create_authority_band_path(authority_id: authority.id), params: m.merge(authority_band: { min_amount: 0, max_amount: 10_000 })
    post dashboard_create_authority_band_path(authority_id: authority.id), params: m.merge(authority_band: { min_amount: 5_000, max_amount: 20_000 })

    assert_equal 1, authority.reload.bands.count
    assert_includes flash[:alert], I18n.t("doa.errors.bands_overlap")
  end

  test "each band shows six boxes and a holder can be a unit or a person" do
    authority = @company.authorities.create!(matrix: @matrix, name_en: "Approve purchase orders")
    band = authority.bands.sole

    post dashboard_create_authority_assignment_path(band_id: band.id), params: m.merge(holder: "unit:#{@procurement.id}",
      authority_assignment: { level: "prepare" })
    post dashboard_create_authority_assignment_path(band_id: band.id), params: m.merge(holder: "user:#{@colleague.id}",
      authority_assignment: { level: "authorize" })

    assignments = band.reload.assignments
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
    band = @company.authorities.create!(matrix: @matrix, name_en: "X").bands.sole

    post dashboard_create_authority_assignment_path(band_id: band.id), params: m.merge(holder: "user:#{stranger.id}",
      authority_assignment: { level: "authorize" })

    assert_equal 0, band.reload.assignments.count
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

  test "an authority keeps at least one band" do
    authority = @company.authorities.create!(matrix: @matrix, name_en: "X")
    delete dashboard_destroy_authority_band_path(authority.bands.sole), params: m

    assert_equal 1, authority.reload.bands.count
    assert_includes flash[:alert], I18n.t("doa.flash.last_band")
  end

  test "an empty matrix does not claim every authority is in order" do
    get dashboard_authorities_path(m)

    assert_includes response.body, I18n.t("doa.findings.nothing_yet")
    assert_not_includes response.body, I18n.t("doa.findings.none")
  end
end
