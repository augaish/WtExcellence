require "test_helper"

# The check that replaces a person comparing two spreadsheets side by side.
class AuthorityConformanceCheckTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Conf Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @minister = @company.org_units.create!(name_en: "Minister", level: 1)
    @deputy = @company.org_units.create!(name_en: "Deputy", level: 2, parent: @minister)
    @director = @company.org_units.create!(name_en: "Director", level: 3, parent: @deputy)

    @matrix = @company.pp_records.create!(record_type: "executive_doa", title_en: "Executive DoA")
    @authority = @company.authorities.create!(matrix: @matrix, name_en: "Sign contracts")
    @authority.bands.sole.assignments.create!(level: "authorize", org_unit: @deputy)

    @process = @company.pp_processes.create!(name_en: "Contracting", level: 1, category: "core")
    @operational = @process.authorities.create!(decision: "Award the contract", authority: @authority)
  end

  def check
    AuthorityConformanceCheck.new(@process.reload)
  end

  test "authorizing at the same level as the executive matrix conforms" do
    @operational.assignments.create!(level: "authorize", org_unit: @deputy)

    assert_not check.any?
  end

  test "authorizing higher up the hierarchy conforms" do
    # «أي صلاحية مفوضة لمسؤول يمكن ممارستها من المسؤول الأعلى له»
    @operational.assignments.create!(level: "authorize", org_unit: @minister)

    assert_not check.any?
  end

  test "authorizing lower down the hierarchy is a breach" do
    @operational.assignments.create!(level: "authorize", org_unit: @director)

    findings = check.findings
    assert_equal 1, findings.size
    assert_equal "authorizes_below_executive", findings.first.kind
    assert_includes findings.first.message, "3"
  end

  test "a decision that claims no executive authority is not judged" do
    unlinked = @process.authorities.create!(decision: "Order stationery")
    unlinked.assignments.create!(level: "authorize", org_unit: @director)

    assert_empty check.findings.select { |finding| finding.operational == unlinked }
    assert_not_includes check.linked_rows, unlinked
  end

  test "an executive authorizer that is not an org unit cannot be compared, and says so" do
    @authority.bands.sole.assignments.destroy_all
    @authority.bands.sole.assignments.create!(level: "authorize", dynamic_role: "owning_unit")
    @operational.assignments.create!(level: "authorize", org_unit: @director)

    assert_equal "executive_unresolvable", check.findings.sole.kind
  end

  test "an operational row with no final authorizer is left to the matrix's own rules" do
    @operational.assignments.create!(level: "prepare", org_unit: @director)

    assert_not check.any?, "the missing authorizer is reported by the operational matrix, not by conformance"
  end

  test "the strictest executive band sets the bar" do
    # The default band is unbounded, so it must be bounded before a second one
    # can exist without the two claiming the same amount.
    @authority.bands.sole.update!(max_amount: 1_000_000)
    band = @authority.bands.create!(min_amount: 1_000_000)
    band.assignments.create!(level: "authorize", org_unit: @minister)
    @operational.assignments.create!(level: "authorize", org_unit: @deputy)

    findings = check.findings
    assert_equal 1, findings.size, "level 2 is below the minister's level 1"
  end
end
