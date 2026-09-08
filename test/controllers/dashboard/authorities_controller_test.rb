require "test_helper"

class Dashboard::AuthoritiesControllerTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!

    @company = Company.create!(name: "DoA Co #{SecureRandom.hex(4)}", license_seats: 10, credits: 50, is_active: true)
    @admin = create_user("doa-admin", CompanyUser::ROLES[:company_admin])
    @viewer = create_user("doa-viewer", CompanyUser::ROLES[:company_viewer])

    @matrix = @company.pp_records.create!(record_type: "executive_doa", title_en: "Executive DoA 2026")
    @category = @company.authority_categories.create!(name_en: "Contracting")
    @minister = @company.org_units.create!(name_en: "Minister", level: 1)
  end

  def create_user(prefix, role)
    user = User.create!(email: "#{prefix}-#{SecureRandom.hex(4)}@example.com",
      password: "password123", password_confirmation: "password123", name: prefix, is_active: true)
    CompanyUser.create!(company: @company, user: user, role: role)
    user
  end

  test "a company with no matrix is told how to start one" do
    @matrix.destroy
    sign_in @admin
    get dashboard_authorities_path

    assert_response :success
    assert_includes response.body, I18n.t("doa.no_matrix")
  end

  test "the matrix lists a level column per authority level" do
    sign_in @admin
    @company.authorities.create!(matrix: @matrix, authority_category: @category, name_en: "Sign contracts")

    get dashboard_authorities_path
    assert_response :success
    AuthorityLevel::KEYS.each { |key| assert_select "th", text: AuthorityLevel.label(key) }
  end

  test "an authority can be added and appears under its category" do
    sign_in @admin
    post dashboard_create_authority_path, params: {
      matrix_id: @matrix.id,
      authority: { authority_category_id: @category.id, name_en: "Sign contracts" }
    }

    assert_redirected_to dashboard_authorities_path(matrix_id: @matrix.id)
    authority = @matrix.authorities.sole
    assert_equal 1, authority.number
    assert_equal 1, authority.bands.count, "an authority is created with one unbounded band"

    follow_redirect!
    assert_includes response.body, "Sign contracts"
    assert_includes response.body, "Contracting"
  end

  test "the findings report names an authority nobody may authorize" do
    @company.authorities.create!(matrix: @matrix, authority_category: @category, name_en: "Sign contracts")

    sign_in @admin
    get dashboard_authorities_path

    assert_includes response.body, I18n.t("doa.findings.no_authorizer")
    assert_includes response.body, I18n.t("doa.findings.missing_basis")
  end

  test "an authority with a single authorizer and a basis raises no findings" do
    policy = @company.pp_records.create!(record_type: "policy", title_en: "Contracting Policy")
    authority = @company.authorities.create!(matrix: @matrix, authority_category: @category,
      name_en: "Sign contracts", basis_record: policy)
    authority.bands.sole.assignments.create!(level: "authorize", org_unit: @minister)

    sign_in @admin
    get dashboard_authorities_path

    assert_includes response.body, I18n.t("doa.findings.none")
  end

  test "a holder can be assigned by unit or by dynamic role" do
    authority = @company.authorities.create!(matrix: @matrix, authority_category: @category, name_en: "Sign contracts")
    band = authority.bands.sole

    sign_in @admin
    post dashboard_create_authority_assignment_path(band_id: band.id), params: {
      matrix_id: @matrix.id,
      authority_assignment: { level: "authorize", org_unit_id: @minister.id }
    }
    post dashboard_create_authority_assignment_path(band_id: band.id), params: {
      matrix_id: @matrix.id,
      authority_assignment: { level: "review", dynamic_role: "owning_unit", condition: "Where above SAR 1m" }
    }

    levels = band.reload.assignments.map(&:level)
    assert_equal %w[authorize review], levels.sort.reverse.sort
    assert_equal "Where above SAR 1m", band.assignments.find_by(level: "review").condition
  end

  test "overlapping bands are refused with a readable reason" do
    authority = @company.authorities.create!(matrix: @matrix, authority_category: @category, name_en: "Sign contracts")
    authority.bands.sole.update!(max_amount: 3_000_000)

    sign_in @admin
    post dashboard_create_authority_band_path(authority_id: authority.id), params: {
      matrix_id: @matrix.id,
      authority_band: { min_amount: 1_000_000, max_amount: 5_000_000 }
    }

    assert_equal 1, authority.reload.bands.count
    assert_includes flash[:alert], I18n.t("doa.errors.bands_overlap")
  end

  test "a viewer can read the matrix but not change it" do
    sign_in @viewer
    get dashboard_authorities_path
    assert_response :success

    post dashboard_create_authority_path, params: {
      matrix_id: @matrix.id, authority: { name_en: "Sneak" }
    }
    assert_redirected_to dashboard_authorities_path
    assert_equal 0, @matrix.authorities.count
  end

  test "opening the next version copies the matrix and shows no changes yet" do
    authority = @company.authorities.create!(matrix: @matrix, name_en: "Sign contracts")
    authority.bands.sole.assignments.create!(level: "authorize", org_unit: @minister)

    sign_in @admin
    post dashboard_open_next_authority_version_path(matrix_id: @matrix.id)

    successor = @company.pp_records.of_type("executive_doa").order(:version_number).last
    assert_equal 2, successor.version_number
    assert_redirected_to dashboard_authorities_path(matrix_id: successor.id)

    follow_redirect!
    assert_includes response.body, I18n.t("doa.diff.none")
  end

  test "a change to the new version is reported against the previous one" do
    @company.authorities.create!(matrix: @matrix, name_en: "Sign contracts")
    successor = AuthorityMatrixVersionService.open_next(@matrix.reload)
    successor.authorities.sole.update!(name_en: "Sign contracts and agreements")

    sign_in @admin
    get dashboard_authorities_path(matrix_id: successor.id)

    assert_includes response.body, I18n.t("doa.diff.amended")
    assert_includes response.body, I18n.t("doa.diff.aspects.name")
  end

  test "an objection can be raised and then ruled on" do
    authority = @company.authorities.create!(matrix: @matrix, name_en: "Sign contracts")

    sign_in @admin
    post dashboard_create_authority_consultation_path(matrix_id: @matrix.id), params: {
      authority_consultation: { authority_id: authority.id, org_unit_id: @minister.id,
                                challenge: "Approval sits with the wrong deputy",
                                proposal: "Move approval to the concerned agency",
                                expected_impact: "Confidential data stays with its owner" }
    }

    consultation = @matrix.consultations.sole
    assert_equal "open", consultation.status
    assert_equal @admin, consultation.raised_by

    patch dashboard_rule_authority_consultation_path(consultation, matrix_id: @matrix.id), params: {
      authority_consultation: { status: "deferred", ruling: "Operational; handle it in the procedure." }
    }

    consultation.reload
    assert_equal "deferred", consultation.status
    assert_equal @admin, consultation.ruled_by
    assert_not_nil consultation.ruled_at
  end

  test "an objection cannot be closed without a ruling" do
    sign_in @admin
    post dashboard_create_authority_consultation_path(matrix_id: @matrix.id), params: {
      authority_consultation: { challenge: "Something is wrong" }
    }
    consultation = @matrix.consultations.sole

    patch dashboard_rule_authority_consultation_path(consultation, matrix_id: @matrix.id), params: {
      authority_consultation: { status: "rejected", ruling: "" }
    }

    assert_equal "open", consultation.reload.status
  end

  test "a delegation can be recorded and shows as in force" do
    authority = @company.authorities.create!(matrix: @matrix, name_en: "Sign contracts")
    deputy = @company.org_units.create!(name_en: "Deputy", level: 2, parent: @minister)

    sign_in @admin
    post dashboard_create_authority_delegation_path(matrix_id: @matrix.id), params: {
      authority_delegation: { authority_id: authority.id, from_org_unit_id: @minister.id,
                              to_org_unit_id: deputy.id, kind: "temporary", status: "active",
                              valid_from: Date.current.to_s, valid_to: (Date.current + 14).to_s }
    }

    delegation = @company.authority_delegations.sole
    assert delegation.in_force?

    # Ending inside the warning window, it is flagged before it lapses rather
    # than simply reported as in force.
    assert delegation.expiring_soon?
    follow_redirect!
    assert_includes response.body,
      I18n.t("doa.delegation.expiring", days: AuthorityDelegation::EXPIRY_LEAD_DAYS)
  end

  test "a delegation beyond what the holder may decide is refused" do
    authority = @company.authorities.create!(matrix: @matrix, name_en: "Sign contracts")
    authority.bands.sole.update!(max_amount: 1_000_000)
    authority.bands.sole.assignments.create!(level: "authorize", org_unit: @minister)
    deputy = @company.org_units.create!(name_en: "Deputy", level: 2, parent: @minister)

    sign_in @admin
    post dashboard_create_authority_delegation_path(matrix_id: @matrix.id), params: {
      authority_delegation: { authority_id: authority.id, from_org_unit_id: @minister.id,
                              to_org_unit_id: deputy.id, kind: "permanent", status: "active",
                              limit_amount: 9_000_000 }
    }

    assert_equal 0, @company.authority_delegations.count
    assert_includes flash[:alert], "1000000"
  end

  test "revoking a delegation records who did it and why" do
    authority = @company.authorities.create!(matrix: @matrix, name_en: "Sign contracts")
    deputy = @company.org_units.create!(name_en: "Deputy", level: 2, parent: @minister)
    delegation = @company.authority_delegations.create!(authority: authority, from_org_unit: @minister,
      to_org_unit: deputy, kind: "permanent", status: "active")

    sign_in @admin
    patch dashboard_revoke_authority_delegation_path(delegation, matrix_id: @matrix.id), params: {
      authority_delegation: { revocation_reason: "The postholder returned." }
    }

    delegation.reload
    assert delegation.revoked?
    assert_equal @admin, delegation.revoked_by
    assert_not delegation.in_force?
  end

  test "another company's matrix is not reachable" do
    other = Company.create!(name: "Other #{SecureRandom.hex(4)}", license_seats: 5, credits: 1, is_active: true)
    foreign = other.pp_records.create!(record_type: "executive_doa", title_en: "Foreign DoA")

    sign_in @admin
    get dashboard_authorities_path(matrix_id: foreign.id)

    assert_response :success
    assert_not_includes response.body, "Foreign DoA"
  end
end
