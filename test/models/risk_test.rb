require "test_helper"

class RiskTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(
      name: "Risk Test Co #{SecureRandom.hex(4)}",
      license_seats: 5,
      is_active: true
    )
  end

  test "calculates inherent score from likelihood and impact" do
    risk = Risk.create!(company: @company, title: "Vendor outage", likelihood: 4, impact: 5)

    assert_equal 20, risk.inherent_score
    assert_equal "critical", risk.inherent_level
  end

  test "calculates residual score only when both residual fields present" do
    risk = Risk.create!(company: @company, title: "Vendor outage", likelihood: 4, impact: 5)

    assert_nil risk.residual_score

    risk.update!(residual_likelihood: 2, residual_impact: 2)

    assert_equal 4, risk.residual_score
    assert_equal "low", risk.residual_level
  end

  test "requires title" do
    risk = Risk.new(company: @company, likelihood: 1, impact: 1)

    refute risk.valid?
    assert_includes risk.errors[:title], "can't be blank"
  end

  test "requires likelihood and impact within 1..5" do
    risk = Risk.new(company: @company, title: "Out of range", likelihood: 6, impact: 0)

    refute risk.valid?
    assert_includes risk.errors[:likelihood], "is not included in the list"
    assert_includes risk.errors[:impact], "is not included in the list"
  end

  test "soft_delete! excludes risk from active scope" do
    risk = Risk.create!(company: @company, title: "Vendor outage", likelihood: 3, impact: 3)

    risk.soft_delete!

    assert risk.deleted?
    refute_includes Risk.active.where(company: @company), risk
  end

  test "defaults to identified status" do
    risk = Risk.create!(company: @company, title: "New risk", likelihood: 2, impact: 2)

    assert_equal "identified", risk.status
  end
end
