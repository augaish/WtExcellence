require "test_helper"

# The review asked each governance module to answer "what changed, by whom, and
# when". Risk answered it with a hand-written method; Vendor and Customer
# Commitment did not answer it at all.
class GovernanceActivityTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Act Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @user = User.create!(email: "act-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: "Actor", is_active: true)
    Thread.current[:current_user] = @user
  end

  teardown { Thread.current[:current_user] = nil }

  test "all three governance records keep an activity trail" do
    risk = @company.risks.create!(title: "Supplier outage", likelihood: 3, impact: 4)
    vendor = @company.vendors.create!(name: "Cloud Co")
    commitment = @company.customer_commitments.create!(title: "Monthly report", customer_name: "Ministry")

    [ risk, vendor, commitment ].each do |record|
      assert_equal 1, record.activity_trail.size, "#{record.class} logged no creation"
      assert_equal @user, record.activity_trail.first.actor_user
    end
  end

  test "a material change records its old and new value" do
    risk = @company.risks.create!(title: "Supplier outage", likelihood: 3, impact: 4)
    risk.update!(likelihood: 5)

    entry = risk.activity_trail.first
    assert_equal "UPDATE_RISK", entry.action
    assert_equal [ 3, 5 ], entry.payload_json.dig("changes", "likelihood")
  end

  test "a vendor risk-level change is now recorded, where it was not before" do
    vendor = @company.vendors.create!(name: "Cloud Co", risk_level: "unassessed")
    vendor.update!(risk_level: "critical", rating_override_reason: "Outage last quarter")

    entry = vendor.activity_trail.first
    assert_equal "UPDATE_VENDOR", entry.action
    assert_equal %w[unassessed critical], entry.payload_json.dig("changes", "risk_level")
  end

  test "a commitment fulfilment is recorded with its basis" do
    commitment = @company.customer_commitments.create!(title: "Monthly report",
      customer_name: "Ministry", due_date: Date.current + 5)
    commitment.update!(status: "fulfilled", fulfillment_note: "Delivered and accepted.")

    changes = commitment.activity_trail.first.payload_json["changes"]
    assert_equal %w[open fulfilled], changes["status"]
    assert_equal [ nil, "Delivered and accepted." ], changes["fulfillment_note"]
  end

  test "an immaterial change writes no entry" do
    vendor = @company.vendors.create!(name: "Cloud Co")
    before = vendor.activity_trail.size

    vendor.update!(notes: "Some internal note")

    assert_equal before, vendor.reload.activity_trail.size,
      "tracking every column would bury the changes that matter"
  end

  test "a change with no actor writes no entry rather than an anonymous one" do
    vendor = @company.vendors.create!(name: "Cloud Co")
    before = vendor.activity_trail.size

    Thread.current[:current_user] = nil
    vendor.update!(risk_level: "critical", rating_override_reason: "Outage last quarter")

    assert_equal before, vendor.reload.activity_trail.size
  end

  test "the trail reads newest first" do
    risk = @company.risks.create!(title: "Supplier outage", likelihood: 3, impact: 4)
    risk.update!(likelihood: 4)
    risk.update!(impact: 5)

    actions = risk.activity_trail.map(&:action)
    assert_equal [ "UPDATE_RISK", "UPDATE_RISK", "CREATE_RISK" ], actions
  end
end
