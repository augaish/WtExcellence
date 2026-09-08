require "test_helper"

# F21 — a risk moved straight from Identified to Closed with no closure reason,
# reviewer, or record of the decision.
class RiskClosureTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Risk Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @user = User.create!(email: "risk-#{SecureRandom.hex(4)}@example.com",
      password: "password123", password_confirmation: "password123", name: "Risk Owner", is_active: true)
    @risk = Risk.create!(company: @company, title: "Supplier outage", likelihood: 3, impact: 4)
  end

  test "a risk cannot be closed without a reason" do
    @risk.status = "closed"

    assert_not @risk.save
    assert_includes @risk.errors[:closure_reason], "can't be blank"
  end

  test "closing a risk records the reason, the actor, and the time" do
    Thread.current[:current_user] = @user
    @risk.update!(status: "closed", closure_reason: "Supplier replaced; exposure removed.")

    assert @risk.closed?
    assert_equal "Supplier replaced; exposure removed.", @risk.closure_reason
    assert_equal @user, @risk.closed_by
    assert_not_nil @risk.closed_at
  ensure
    Thread.current[:current_user] = nil
  end

  test "reopening a risk clears the closure record" do
    @risk.update!(status: "closed", closure_reason: "Mitigated.")
    @risk.update!(status: "monitoring")

    assert_nil @risk.closed_at
    assert_nil @risk.closed_by
    assert_nil @risk.closure_reason
  end

  test "a risk closed before the requirement existed can still be edited" do
    @risk.update_columns(status: "closed", closure_reason: nil)
    @risk.reload

    assert @risk.update(description: "Added context")
  end
end
