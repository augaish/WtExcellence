require "test_helper"

# F22 — none of the three registers could be searched or filtered, so a manager
# could not reach "my overdue treatments" or "critical vendors awaiting review"
# without reading the whole list.
class GovernanceRegisterFilterTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Filter Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @user = User.create!(email: "filter-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: "Owner", is_active: true)
    @membership = CompanyUser.create!(company: @company, user: @user, role: CompanyUser::ROLES[:company_admin])
  end

  def filter_for(scope, params)
    GovernanceRegisterFilter.new(scope, params: ActionController::Parameters.new(params).permit!,
      company_user: @membership, company: @company)
  end

  test "search matches the columns that identify a record" do
    match = @company.risks.create!(title: "Supplier outage", likelihood: 3, impact: 3)
    @company.risks.create!(title: "Data loss", likelihood: 2, impact: 2)

    results = filter_for(@company.risks, q: "supplier").results
    assert_equal [ match.id ], results.map(&:id)
  end

  test "search is not confused by wildcard characters" do
    @company.risks.create!(title: "Supplier outage", likelihood: 3, impact: 3)

    assert_empty filter_for(@company.risks, q: "%").results.to_a,
      "a bare wildcard should match nothing rather than everything"
  end

  test "mine returns only what the signed-in member owns" do
    mine = @company.risks.create!(title: "Mine", likelihood: 3, impact: 3, owner: @membership)
    @company.risks.create!(title: "Someone else's", likelihood: 3, impact: 3)

    assert_equal [ mine.id ], filter_for(@company.risks, queue: "mine").results.map(&:id)
  end

  test "mine shows nothing rather than everything when nobody is signed in" do
    @company.risks.create!(title: "A risk", likelihood: 3, impact: 3)
    filter = GovernanceRegisterFilter.new(@company.risks,
      params: ActionController::Parameters.new(queue: "mine").permit!, company_user: nil, company: @company)

    assert_empty filter.results.to_a
  end

  test "above appetite uses current exposure and needs an appetite to exist" do
    high = @company.risks.create!(title: "High", likelihood: 5, impact: 5)
    @company.risks.create!(title: "Low", likelihood: 1, impact: 1)

    assert_empty filter_for(@company.risks, queue: "above_appetite").results.to_a,
      "with no appetite set, nothing can be above it"

    @company.update!(risk_appetite_score: 10)
    assert_equal [ high.id ], filter_for(@company.risks, queue: "above_appetite").results.map(&:id)

    # A residual assessment lowers current exposure below the threshold.
    high.update!(residual_likelihood: 1, residual_impact: 1, control_rationale: "Controls in place")
    assert_empty filter_for(@company.risks, queue: "above_appetite").results.to_a
  end

  test "vendor queues separate unassessed from critical" do
    unassessed = @company.vendors.create!(name: "Newcomer")
    critical = @company.vendors.create!(name: "Core platform", risk_level: "critical", rating_override_reason: "Outage last quarter")

    assert_equal [ unassessed.id ], filter_for(@company.vendors, queue: "unassessed").results.map(&:id)
    assert_equal [ critical.id ], filter_for(@company.vendors, queue: "critical").results.map(&:id)
  end

  test "commitment queues separate overdue, due soon and fulfilled" do
    overdue = @company.customer_commitments.create!(title: "Late", customer_name: "A", due_date: Date.current - 2)
    soon = @company.customer_commitments.create!(title: "Soon", customer_name: "B", due_date: Date.current + 3)
    @company.customer_commitments.create!(title: "Later", customer_name: "C", due_date: Date.current + 200)
    done = @company.customer_commitments.create!(title: "Done", customer_name: "D", due_date: Date.current - 1,
      status: "fulfilled", fulfillment_note: "Delivered.")

    assert_equal [ overdue.id ], filter_for(@company.customer_commitments, queue: "overdue").results.map(&:id)
    assert_equal [ soon.id ], filter_for(@company.customer_commitments, queue: "due_soon").results.map(&:id)
    assert_equal [ done.id ], filter_for(@company.customer_commitments, queue: "fulfilled").results.map(&:id)
  end

  test "a fulfilled commitment is never overdue, however late it was" do
    @company.customer_commitments.create!(title: "Late but done", customer_name: "A",
      due_date: Date.current - 30, status: "fulfilled", fulfillment_note: "Delivered late.")

    assert_empty filter_for(@company.customer_commitments, queue: "overdue").results.to_a
  end

  test "queue counts describe what clicking would show, including the search" do
    @company.risks.create!(title: "Supplier outage", likelihood: 3, impact: 3, owner: @membership)
    @company.risks.create!(title: "Supplier fraud", likelihood: 3, impact: 3)
    @company.risks.create!(title: "Data loss", likelihood: 3, impact: 3, owner: @membership)

    counts = filter_for(@company.risks, q: "supplier").queue_counts
    assert_equal 2, counts["all"]
    assert_equal 1, counts["mine"], "the count must respect the search, not ignore it"
  end

  test "an unknown queue falls back to all rather than returning nothing" do
    @company.risks.create!(title: "A risk", likelihood: 3, impact: 3)

    filter = filter_for(@company.risks, queue: "not_a_queue")
    assert_equal "all", filter.queue
    assert_equal 1, filter.results.count
  end
end
