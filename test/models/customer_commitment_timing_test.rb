require "test_helper"

# F20 and the commitments half of F21: timing was a status a user could pick,
# and fulfilment recorded nothing about when it happened or on what basis.
class CustomerCommitmentTimingTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Commit Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @user = User.create!(email: "commit-#{SecureRandom.hex(4)}@example.com",
      password: "password123", password_confirmation: "password123", name: "Owner", is_active: true)
    @commitment = @company.customer_commitments.create!(title: "Monthly service report",
      customer_name: "Ministry of Tourism", due_date: Date.current + 60)
  end

  teardown { Thread.current[:current_user] = nil }

  test "overdue is not a status anyone can choose" do
    assert_equal %w[open in_progress fulfilled], CustomerCommitment.statuses.keys
  end

  test "timing is derived from the due date, not from the status" do
    assert_equal "not_due", @commitment.timing_state

    @commitment.update!(due_date: Date.current + 5)
    assert_equal "due_soon", @commitment.timing_state

    @commitment.update!(due_date: Date.current - 4)
    assert_equal "overdue", @commitment.timing_state
    assert_equal 4, @commitment.days_overdue
  end

  test "an obligation with no due date has no timing to report" do
    @commitment.update!(due_date: nil)

    assert_equal "no_due_date", @commitment.timing_state
    assert_equal 0, @commitment.days_overdue
  end

  test "fulfilment requires a basis" do
    @commitment.status = "fulfilled"

    assert_not @commitment.save
    assert_includes @commitment.errors[:fulfillment_note], "can't be blank"
  end

  test "fulfilment stamps the time and the person, and cannot be typed" do
    Thread.current[:current_user] = @user
    @commitment.update!(status: "fulfilled", fulfillment_note: "Report delivered and accepted.")

    assert_not_nil @commitment.fulfilled_at
    assert_equal @user, @commitment.fulfilled_by
  end

  test "late fulfilment stays identifiable" do
    @commitment.update!(due_date: Date.current - 3)
    @commitment.update!(status: "fulfilled", fulfillment_note: "Delivered after the deadline.")

    assert @commitment.fulfilled_late?
    assert_equal "fulfilled_late", @commitment.timing_state
    assert_equal 3, @commitment.days_overdue
  end

  test "on-time fulfilment is told apart from late fulfilment" do
    @commitment.update!(status: "fulfilled", fulfillment_note: "Delivered early.")

    assert_not @commitment.fulfilled_late?
    assert_equal "fulfilled_on_time", @commitment.timing_state
  end

  test "reopening a fulfilled obligation clears the fulfilment record" do
    @commitment.update!(status: "fulfilled", fulfillment_note: "Delivered.")
    @commitment.update!(status: "in_progress")

    assert_nil @commitment.fulfilled_at
    assert_nil @commitment.fulfilled_by
    assert_nil @commitment.fulfillment_note
  end

  test "an obligation fulfilled before the requirement existed stays editable" do
    @commitment.update_columns(status: "fulfilled", fulfillment_note: nil)

    assert @commitment.reload.update(description: "Added context")
  end

  test "past due excludes fulfilled obligations" do
    late = @company.customer_commitments.create!(title: "Late one", customer_name: "X", due_date: Date.current - 1)
    @commitment.update!(due_date: Date.current - 1, status: "fulfilled", fulfillment_note: "Done.")

    assert_equal [ late ], @company.customer_commitments.past_due.to_a
  end
end
