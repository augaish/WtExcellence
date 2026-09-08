require "test_helper"

# The rules the guiding principles state in prose and no register can check for
# itself.
class AuthorityDelegationTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Del Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @minister = @company.org_units.create!(name_en: "Minister", level: 1)
    @deputy = @company.org_units.create!(name_en: "Deputy", level: 2, parent: @minister)
    @director = @company.org_units.create!(name_en: "Director", level: 3, parent: @deputy)
    @user = User.create!(email: "del-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: "Grantor", is_active: true)

    @matrix = @company.pp_records.create!(record_type: "executive_doa", title_en: "Executive DoA")
    @authority = @company.authorities.create!(matrix: @matrix, name_en: "Sign contracts")
    # The minister may decide up to SAR 3m under this authority.
    @authority.bands.sole.update!(max_amount: 3_000_000)
    @authority.bands.sole.assignments.create!(level: "authorize", org_unit: @minister)
  end

  teardown { Thread.current[:current_user] = nil }

  def delegation(**attributes)
    @company.authority_delegations.new({
      authority: @authority, from_org_unit: @minister, to_org_unit: @deputy,
      kind: "temporary", valid_from: Date.current, valid_to: Date.current + 14, status: "active"
    }.merge(attributes))
  end

  test "a delegation is between positions, not people" do
    record = delegation
    assert record.save
    assert_equal @minister, record.from_org_unit
    assert_equal @deputy, record.to_org_unit
  end

  test "a position cannot delegate to itself" do
    record = delegation(to_org_unit: @minister)

    assert_not record.valid?
    assert_predicate record.errors[:to_org_unit], :present?
  end

  test "a temporary delegation must say when it ends" do
    record = delegation(valid_to: nil)

    assert_not record.valid?
    assert_predicate record.errors[:valid_to], :present?
  end

  test "a permanent delegation needs no end date" do
    assert delegation(kind: "permanent", valid_to: nil).valid?
  end

  test "nobody may delegate more than they hold" do
    too_much = delegation(limit_amount: 5_000_000)

    assert_not too_much.valid?
    assert_includes too_much.errors[:limit_amount].to_sentence, "3000000"

    assert delegation(limit_amount: 1_000_000).valid?, "delegating less than held is the normal case"
  end

  test "a delegate with no stated cap inherits the holder's" do
    assert_equal 3_000_000, delegation.tap(&:save!).effective_limit
    assert_equal 1_000_000, delegation(limit_amount: 1_000_000).tap(&:save!).effective_limit
  end

  test "a temporary delegation stops conferring authority the day after it lapses" do
    record = delegation(valid_from: Date.current - 10, valid_to: Date.current - 1)
    record.save!

    assert_not record.in_force?
    assert record.expired?
    assert record.in_force?(Date.current - 5)
  end

  test "a delegation that has not started yet is not in force" do
    record = delegation(valid_from: Date.current + 5, valid_to: Date.current + 20)
    record.save!

    assert_not record.in_force?
    assert record.in_force?(Date.current + 6)
  end

  test "delegations nearing expiry can be found before they lapse" do
    soon = delegation(valid_to: Date.current + 10)
    soon.save!
    later = delegation(to_org_unit: @director, valid_to: Date.current + 200)
    later.save!

    assert soon.expiring_soon?
    assert_not later.expiring_soon?
    assert_equal [ soon ], @company.authority_delegations.expiring_before(Date.current + 30).to_a
  end

  test "delegating back to the original holder is refused" do
    delegation.save!
    reverse = @company.authority_delegations.new(authority: @authority, from_org_unit: @deputy,
      to_org_unit: @minister, kind: "permanent", status: "active")

    assert_not reverse.valid?
    assert_predicate reverse.errors[:base], :present?
  end

  test "a sub-delegation needs the original grantor's approval to be active" do
    parent = delegation
    parent.save!

    sub = @company.authority_delegations.new(authority: @authority, from_org_unit: @deputy,
      to_org_unit: @director, kind: "permanent", status: "active", parent_delegation: parent)

    assert_not sub.valid?
    assert_predicate sub.errors[:base], :present?

    sub.grantor_approved_by = @user
    assert sub.valid?
  end

  test "a sub-delegation may be drafted before it is approved" do
    parent = delegation
    parent.save!

    assert @company.authority_delegations.new(authority: @authority, from_org_unit: @deputy,
      to_org_unit: @director, kind: "permanent", status: "draft", parent_delegation: parent).valid?
  end

  test "a sub-delegation cannot itself be delegated onward" do
    parent = delegation
    parent.save!
    sub = @company.authority_delegations.create!(authority: @authority, from_org_unit: @deputy,
      to_org_unit: @director, kind: "permanent", status: "active",
      parent_delegation: parent, grantor_approved_by: @user)

    fourth = @company.org_units.create!(name_en: "Head of Section", level: 4, parent: @director)
    second_hop = @company.authority_delegations.new(authority: @authority, from_org_unit: @director,
      to_org_unit: fourth, kind: "permanent", status: "active",
      parent_delegation: sub, grantor_approved_by: @user)

    assert_not second_hop.valid?
    assert_predicate second_hop.errors[:base], :present?
  end

  test "accountability stays with the original holder however long the chain" do
    parent = delegation
    parent.save!
    sub = @company.authority_delegations.create!(authority: @authority, from_org_unit: @deputy,
      to_org_unit: @director, kind: "permanent", status: "active",
      parent_delegation: parent, grantor_approved_by: @user)

    assert_equal @minister, sub.accountable_unit
  end

  test "revoking a delegation requires a reason and records who did it" do
    record = delegation
    record.save!

    record.status = "revoked"
    assert_not record.save
    assert_predicate record.errors[:revocation_reason], :present?

    Thread.current[:current_user] = @user
    record.revocation_reason = "The postholder returned from leave."
    assert record.save
    assert_equal @user, record.revoked_by
    assert_not_nil record.revoked_at
    assert_not record.in_force?
  end

  test "a delegation cannot cross companies" do
    other = Company.create!(name: "Other #{SecureRandom.hex(4)}", license_seats: 5, credits: 1, is_active: true)
    foreign = other.org_units.create!(name_en: "Foreign", level: 1)

    record = delegation(to_org_unit: foreign)
    assert_not record.valid?
    assert_predicate record.errors[:to_org_unit], :present?
  end
end
