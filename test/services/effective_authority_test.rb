require "test_helper"

class EffectiveAuthorityTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Eff Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @minister = @company.org_units.create!(name_en: "Minister", level: 1)
    @deputy = @company.org_units.create!(name_en: "Deputy", level: 2, parent: @minister)
    @director = @company.org_units.create!(name_en: "Director", level: 3, parent: @deputy)

    @matrix = @company.pp_records.create!(record_type: "executive_doa", title_en: "Executive DoA")
    @authority = @company.authorities.create!(matrix: @matrix, name_en: "Award contracts")

    @small = @authority.bands.sole
    @small.update!(max_amount: 3_000_000)
    @small.assignments.create!(level: "authorize", org_unit: @deputy)

    @large = @authority.bands.create!(min_amount: 3_000_000)
    @large.assignments.create!(level: "authorize", org_unit: @minister)
  end

  def effective(on = Date.current)
    EffectiveAuthority.new(@authority.reload, on: on)
  end

  test "the band decides who may authorize an amount" do
    assert_equal [ @deputy ], effective.authorizers_for(1_000_000).map(&:org_unit)
    assert_equal [ @minister ], effective.authorizers_for(5_000_000).map(&:org_unit)
  end

  test "a delegation in force adds the delegate to the answer" do
    @company.authority_delegations.create!(authority: @authority, from_org_unit: @deputy,
      to_org_unit: @director, kind: "temporary", status: "active",
      valid_from: Date.current - 1, valid_to: Date.current + 7)

    holders = effective.authorizers_for(1_000_000)
    assert_equal [ @deputy, @director ], holders.map(&:org_unit)
    assert holders.last.delegated?
  end

  test "a lapsed delegation confers nothing, with nobody having to switch it off" do
    @company.authority_delegations.create!(authority: @authority, from_org_unit: @deputy,
      to_org_unit: @director, kind: "temporary", status: "active",
      valid_from: Date.current - 10, valid_to: Date.current - 1)

    assert_equal [ @deputy ], effective.authorizers_for(1_000_000).map(&:org_unit)
    assert_equal [ @deputy, @director ], effective(Date.current - 5).authorizers_for(1_000_000).map(&:org_unit)
  end

  test "a delegation from a position that does not hold this band adds nobody" do
    # The deputy holds the small band, not the large one.
    @company.authority_delegations.create!(authority: @authority, from_org_unit: @deputy,
      to_org_unit: @director, kind: "permanent", status: "active")

    assert_equal [ @minister ], effective.authorizers_for(5_000_000).map(&:org_unit)
  end

  test "a delegate carries their own cap where one was set" do
    @company.authority_delegations.create!(authority: @authority, from_org_unit: @deputy,
      to_org_unit: @director, kind: "permanent", status: "active", limit_amount: 500_000)

    delegated = effective.authorizers_for(1_000_000).find(&:delegated?)
    assert_equal 500_000, delegated.limit
  end

  test "a revoked delegation confers nothing" do
    delegation = @company.authority_delegations.create!(authority: @authority, from_org_unit: @deputy,
      to_org_unit: @director, kind: "permanent", status: "active")
    delegation.update!(status: "revoked", revocation_reason: "Superseded.")

    assert_equal [ @deputy ], effective.authorizers_for(1_000_000).map(&:org_unit)
  end
end
