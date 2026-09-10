require "test_helper"

# Section 8 of Review 03: a risk carries its statement, treatment, controls,
# review date and an acceptance with expiry; a commitment carries its
# agreement, acceptance criteria, delivery, customer acceptance and recurrence.
class Dashboard::GovernanceDepthTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!
    @company = Company.create!(name: "Depth #{SecureRandom.hex(4)}", license_seats: 10, credits: 50, is_active: true, risk_appetite_score: 8)
    @admin = User.create!(email: "depth-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: "Admin", is_active: true)
    @cu = CompanyUser.create!(company: @company, user: @admin, role: CompanyUser::ROLES[:company_admin])
    sign_in @admin
  end

  test "a risk is stated as cause, event and impact, and a residual score needs its controls" do
    post dashboard_risk_management_index_path, params: { risk: {
      title: "Hosting outage", likelihood: 4, impact: 4, cause: "a single hosting supplier", event: "a prolonged outage",
      impact_statement: "the customer portal being unavailable", residual_likelihood: 2, residual_impact: 4 } }
    assert_response :unprocessable_entity, "a residual score without controls is refused"

    post dashboard_risk_management_index_path, params: { risk: {
      title: "Hosting outage", likelihood: 4, impact: 4, cause: "a single hosting supplier", event: "a prolonged outage",
      impact_statement: "the customer portal being unavailable", residual_likelihood: 2, residual_impact: 4,
      control_rationale: "Daily backups tested monthly; failover rehearsed", treatment_strategy: "reduce",
      control_owner_id: @cu.id, next_review_on: "2027-01-01" } }
    risk = Risk.find_by(title: "Hosting outage")
    assert_match(/Because of a single hosting supplier/, risk.statement(:en))
    assert_equal "reduce", risk.treatment_strategy
    assert_equal 8, risk.residual_score
  end

  test "exposure above appetite needs acceptance with a reason and an expiry, then lapses" do
    risk = Risk.create!(company: @company, title: "Vendor lock-in", likelihood: 4, impact: 4)
    assert risk.needs_acceptance?

    get dashboard_risk_management_path(risk)
    assert_select "body", text: /#{Regexp.escape(I18n.t('risk_depth.needs_acceptance'))}/

    patch dashboard_accept_risk_path(risk), params: { acceptance_rationale: "", acceptance_expires_on: "2027-01-01" }
    refute risk.reload.accepted?
    patch dashboard_accept_risk_path(risk), params: { acceptance_rationale: "Migration planned for Q2", acceptance_expires_on: "2027-01-01" }
    risk.reload
    assert risk.accepted?
    assert_equal @admin, risk.accepted_by
    refute risk.needs_acceptance?

    travel_to Date.new(2027, 2, 1) do
      assert risk.acceptance_expired?
      assert risk.needs_acceptance?
    end
  end

  test "register queues surface risks needing acceptance and overdue reviews" do
    Risk.create!(company: @company, title: "Above", likelihood: 4, impact: 4)
    Risk.create!(company: @company, title: "Stale", likelihood: 1, impact: 1, next_review_on: Date.current - 1)
    get dashboard_risk_management_index_path(queue: "needs_acceptance")
    assert_select "body", text: /Above/
    refute_match(/Stale/, response.body)
    get dashboard_risk_management_index_path(queue: "review_overdue")
    assert_select "body", text: /Stale/
  end

  test "a commitment records its agreement, delivery and the customer's acceptance, and recurs when fulfilled" do
    vendor = Vendor.create!(company: @company, name: "ACME Hosting")
    post dashboard_customer_commitments_path, params: { customer_commitment: {
      title: "Monthly availability report", customer_name: "Bank A", due_date: Date.new(2026, 10, 1), status: "open",
      agreement_reference: "MSA clause 7.2", acceptance_criteria: "Report received by the 5th", recurrence: "monthly", vendor_id: vendor.id } }
    commitment = CustomerCommitment.find_by(title: "Monthly availability report")
    assert_equal vendor, commitment.vendor
    assert_equal "pending", commitment.acceptance_status

    patch acceptance_dashboard_customer_commitment_path(commitment), params: { acceptance_status: "accepted" }
    assert_equal "pending", commitment.reload.acceptance_status, "acceptance is recorded only once fulfilled"

    patch dashboard_customer_commitment_path(commitment), params: { customer_commitment: { status: "fulfilled", fulfillment_note: "Sent", delivered_on: "2026-09-30" } }
    commitment.reload
    assert commitment.fulfilled?
    follow_up = CustomerCommitment.find_by(recurred_from_id: commitment.id)
    assert follow_up, "a recurring obligation opens its next occurrence"
    assert_equal Date.new(2026, 11, 1), follow_up.due_date
    assert_equal "open", follow_up.status

    patch acceptance_dashboard_customer_commitment_path(commitment), params: { acceptance_status: "accepted", acceptance_note: "Confirmed by email" }
    commitment.reload
    assert_equal "accepted", commitment.acceptance_status
    assert_equal @admin, commitment.verified_by

    get dashboard_vendor_path(vendor)
    assert_select "body", text: /Monthly availability report/
  end
end
