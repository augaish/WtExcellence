require "test_helper"

class CustomerCommitmentTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(
      name: "Commitment Test Co #{SecureRandom.hex(4)}",
      license_seats: 5,
      is_active: true
    )
  end

  test "requires title and customer_name" do
    commitment = CustomerCommitment.new(company: @company)

    refute commitment.valid?
    assert_includes commitment.errors[:title], "can't be blank"
    assert_includes commitment.errors[:customer_name], "can't be blank"
  end

  test "defaults to open status" do
    commitment = CustomerCommitment.create!(company: @company, title: "SLA report", customer_name: "Acme Corp")

    assert_equal "open", commitment.status
  end

  test "past_due? is true only when due_date has passed and not fulfilled" do
    commitment = CustomerCommitment.create!(company: @company, title: "SLA report", customer_name: "Acme Corp", due_date: 1.day.ago)

    assert commitment.past_due?

    # Fulfilment must say on what basis the obligation was accepted as met.
    commitment.update!(status: "fulfilled", fulfillment_note: "Report delivered and accepted.")

    refute commitment.past_due?
  end

  test "soft_delete! excludes commitment from active scope" do
    commitment = CustomerCommitment.create!(company: @company, title: "SLA report", customer_name: "Acme Corp")

    commitment.soft_delete!

    assert commitment.deleted?
    refute_includes CustomerCommitment.active.where(company: @company), commitment
  end
end
