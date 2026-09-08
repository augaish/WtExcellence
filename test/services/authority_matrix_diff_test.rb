require "test_helper"

# The diff that replaces the hand-maintained "الاضافات والتعديلات" sheet,
# including its manual "did this change?" column.
class AuthorityMatrixDiffTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Diff Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @minister = @company.org_units.create!(name_en: "Minister", level: 1)
    @deputy = @company.org_units.create!(name_en: "Deputy", level: 2, parent: @minister)

    @v1 = @company.pp_records.create!(record_type: "executive_doa", title_en: "Executive DoA", version_label: "v1")
    @authority = @company.authorities.create!(matrix: @v1, name_en: "Sign contracts", number: 1)
    @authority.bands.sole.assignments.create!(level: "authorize", org_unit: @minister)
  end

  def open_next
    AuthorityMatrixVersionService.open_next(@v1.reload)
  end

  def diff(v2)
    AuthorityMatrixDiff.new(@v1.reload, v2.reload)
  end

  test "opening a version copies the matrix and leaves the approved one untouched" do
    v2 = open_next

    assert_equal "v2", v2.version_label
    assert_equal @v1, v2.previous_version
    assert_equal 1, v2.authorities.count
    assert_equal 1, @v1.reload.authorities.count

    copied = v2.authorities.sole
    assert_equal @authority.stable_key, copied.stable_key, "identity survives so a diff can match the rows"
    assert_equal 1, copied.bands.count
    assert_equal [ "authorize" ], copied.bands.sole.assignments.map(&:level)
  end

  test "an untouched copy reports no changes" do
    assert_not diff(open_next).any?, "copying a matrix is not a change to it"
  end

  test "a new authority reads as added" do
    v2 = open_next
    @company.authorities.create!(matrix: v2, name_en: "Approve donations", number: 2)

    change = diff(v2).changes.sole
    assert_equal "added", change.kind
    assert_equal "Approve donations", change.after.display_name
  end

  test "a deleted authority reads as removed" do
    v2 = open_next
    v2.authorities.sole.destroy

    change = diff(v2).changes.sole
    assert_equal "removed", change.kind
    assert_equal "Sign contracts", change.before.display_name
  end

  test "a renamed authority reads as amended, not as a deletion and an addition" do
    v2 = open_next
    v2.authorities.sole.update!(name_en: "Sign contracts and agreements")

    change = diff(v2).changes.sole
    assert_equal "amended", change.kind
    assert_equal [ "name" ], change.detail
  end

  test "a changed holder is reported as a change of holders" do
    v2 = open_next
    v2.authorities.sole.bands.sole.assignments.sole.update!(org_unit: @deputy)

    change = diff(v2).changes.sole
    assert_equal "amended", change.kind
    assert_equal [ "holders" ], change.detail
  end

  test "a changed threshold is reported as a change of thresholds" do
    v2 = open_next
    v2.authorities.sole.bands.sole.update!(max_amount: 3_000_000)

    change = diff(v2).changes.sole
    assert_includes change.detail, "bands"
  end

  test "a newly recorded basis is reported" do
    policy = @company.pp_records.create!(record_type: "policy", title_en: "Contracting Policy")
    v2 = open_next
    v2.authorities.sole.update!(basis_record: policy)

    assert_equal [ "basis" ], diff(v2).changes.sole.detail
  end

  test "reordering holders is not reported as a change" do
    @authority.bands.sole.assignments.create!(level: "review", org_unit: @deputy)
    v2 = open_next
    v2.authorities.sole.bands.sole.assignments.each_with_index { |a, i| a.update!(sort_order: 10 - i) }

    assert_not diff(v2).any?, "a matrix reordered but not changed has not changed"
  end
end
