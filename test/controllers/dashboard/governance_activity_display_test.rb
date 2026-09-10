require "test_helper"

# The trail has to be readable on the record, not just present in the database.
class Dashboard::GovernanceActivityDisplayTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!

    @company = Company.create!(name: "Trail Co #{SecureRandom.hex(4)}", license_seats: 10, credits: 50, is_active: true)
    @admin = User.create!(email: "trail-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: "Trail Admin", is_active: true)
    CompanyUser.create!(company: @company, user: @admin, role: CompanyUser::ROLES[:company_admin])
  end

  def with_actor
    Thread.current[:current_user] = @admin
    yield
  ensure
    Thread.current[:current_user] = nil
  end

  test "a risk shows what changed, in words" do
    risk = with_actor do
      record = @company.risks.create!(title: "Supplier outage", likelihood: 3, impact: 4)
      record.update!(likelihood: 5)
      record
    end

    sign_in @admin
    get dashboard_risk_management_path(risk)

    assert_response :success
    assert_select "h2", text: I18n.t("governance_activity.title")
    assert_includes response.body, I18n.t("governance_activity.actions.update_risk")
    assert_includes response.body, "Likelihood"
    assert_includes response.body, @admin.name
  end

  test "a vendor shows its risk-level change" do
    vendor = with_actor do
      record = @company.vendors.create!(name: "Cloud Co", risk_level: "unassessed")
      record.update!(risk_level: "critical", rating_override_reason: "Outage last quarter")
      record
    end

    sign_in @admin
    get dashboard_vendor_path(vendor)

    assert_response :success
    assert_includes response.body, I18n.t("governance_activity.actions.update_vendor")
    assert_includes response.body, "critical"
  end

  test "a commitment shows its fulfilment and reads a blank as not set" do
    commitment = with_actor do
      record = @company.customer_commitments.create!(title: "Monthly report",
        customer_name: "Ministry", due_date: Date.current + 5)
      record.update!(status: "fulfilled", fulfillment_note: "Delivered and accepted.")
      record
    end

    sign_in @admin
    get dashboard_customer_commitment_path(commitment)

    assert_response :success
    assert_includes response.body, I18n.t("governance_activity.actions.update_customer_commitment")
    assert_includes response.body, I18n.t("governance_activity.not_set")
  end

  test "a record with no history says so rather than showing an empty list" do
    risk = @company.risks.create!(title: "Untouched", likelihood: 1, impact: 1)

    sign_in @admin
    get dashboard_risk_management_path(risk)

    assert_includes response.body, I18n.t("governance_activity.none")
  end
end
