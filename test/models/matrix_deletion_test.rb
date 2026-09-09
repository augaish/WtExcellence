require "test_helper"

# A matrix version can be removed whatever hangs off it: holders, delegations
# and their sub-delegations, objections, reviews, and the operational
# decisions in procedures that named one of its authorities.
class MatrixDeletionTest < ActiveSupport::TestCase
  test "deleting both versions of a fully used matrix succeeds and unlinks the procedure decisions" do
    company = Company.create!(name: "Del #{SecureRandom.hex(3)}", license_seats: 5, is_active: true)
    unit = company.org_units.create!(name_en: "Unit", level: 1)
    deputy = company.org_units.create!(name_en: "Deputy", level: 2, parent: unit)
    user = User.create!(email: "del-#{SecureRandom.hex(3)}@example.com", password: "password123",
      password_confirmation: "password123", name: "A", is_active: true)

    matrix = company.pp_records.create!(record_type: "executive_doa", title_en: "DoA")
    authority = company.authorities.create!(matrix: matrix, name_en: "Sign", authority_category: company.authority_categories.create!(name_en: "Cat"))
    authority.default_band.assignments.create!(level: "authorize", org_unit: unit)
    delegation = company.authority_delegations.create!(authority: authority, from_org_unit: unit, to_org_unit: deputy,
      kind: "permanent", status: "active", valid_from: Date.current)
    matrix.consultations.create!(authority: authority, org_unit: unit, challenge: "Too high", raised_by: user)
    matrix.matrix_reviews.create!(user: user, requested_at: Time.current)
    procedure = company.pp_records.create!(record_type: "procedure", title_en: "P", pp_process: level_two_process(company))
    decision = procedure.operational_authorities.create!(decision: "Award", authority: authority)
    v2 = AuthorityMatrixVersionService.open_next(matrix, actor: user)

    assert_nothing_raised { v2.reload.destroy! }
    assert_nothing_raised { matrix.reload.destroy! }

    refute Authority.exists?(authority.id)
    refute AuthorityDelegation.exists?(delegation.id)
    assert_nil decision.reload.authority_id, "the procedure keeps its decision, without the link"
    assert PpRecord.exists?(procedure.id)
  end
end
