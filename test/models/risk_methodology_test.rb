require "test_helper"

# Inherent, current residual and target are three different things. The review
# found the first two conflated and the third missing, and warned that a low
# target must never read as mitigation already achieved.
class RiskMethodologyTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Meth Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @risk = @company.risks.create!(title: "Supplier outage", likelihood: 4, impact: 5)
  end

  test "inherent exposure is scored from the inherent assessment" do
    assert_equal 20, @risk.inherent_score
  end

  test "current exposure is the inherent score until a residual assessment exists" do
    assert_equal 20, @risk.current_score

    @risk.update!(residual_likelihood: 2, residual_impact: 2)
    assert_equal 4, @risk.current_score
  end

  test "a target is scored but never treated as the current exposure" do
    @risk.update!(target_likelihood: 1, target_impact: 1)

    assert_equal 1, @risk.target_score
    assert_equal 20, @risk.current_score,
      "an intended target must not be read as exposure already reduced"
    assert_not @risk.target_met?
  end

  test "a target is met only once the residual assessment reaches it" do
    @risk.update!(target_likelihood: 2, target_impact: 2)
    assert_not @risk.target_met?

    @risk.update!(residual_likelihood: 1, residual_impact: 2)
    assert @risk.target_met?
  end

  test "nothing is above appetite until the company sets one" do
    assert_not @risk.above_appetite?, "an unset appetite must not invent a threshold"
  end

  test "exposure above the approved threshold is reported" do
    @company.update!(risk_appetite_score: 10)

    assert @risk.reload.above_appetite?

    @risk.update!(residual_likelihood: 2, residual_impact: 2)
    assert_not @risk.above_appetite?, "appetite is judged on current exposure, not inherent"
  end

  test "the appetite threshold is settable and clearable by an admin" do
    # Covered end to end in the controller test; this guards the model contract.
    # Inherent exposure here is 4 x 5 = 20.
    @company.update!(risk_appetite_score: 12)
    assert @risk.reload.above_appetite?

    @company.update!(risk_appetite_score: 25)
    assert_not @risk.reload.above_appetite?

    @company.update!(risk_appetite_score: nil)
    assert_not @risk.reload.above_appetite?, "clearing the appetite stops anything being above it"
  end

  test "target scores stay within the scale" do
    @risk.target_likelihood = 9

    assert_not @risk.valid?
    assert_predicate @risk.errors[:target_likelihood], :present?
  end
end
