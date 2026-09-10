require "test_helper"

# Q14: a retried submission finds the record already created. Q15: the
# registers offer a card per row on small screens and every CAPA control has
# a name.
class Dashboard::Review3Phase10Test < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!
    @company = Company.create!(name: "P10 #{SecureRandom.hex(4)}", license_seats: 10, credits: 50, is_active: true)
    @admin = User.create!(email: "p10-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: "Admin", is_active: true)
    CompanyUser.create!(company: @company, user: @admin, role: CompanyUser::ROLES[:company_admin])
    sign_in @admin
  end

  test "submitting the same commitment form twice creates one record and lands on it" do
    token = SecureRandom.hex(16)
    params = { submission_token: token, customer_commitment: { title: "Deliver report", customer_name: "ACME", due_date: "2026-12-01", status: "open" } }

    assert_difference -> { CustomerCommitment.count }, 1 do
      post dashboard_customer_commitments_path, params: params
      post dashboard_customer_commitments_path, params: params
    end
    assert_redirected_to dashboard_customer_commitment_path(CustomerCommitment.find_by(submission_token: token))
  end

  test "the new commitment form carries a one-time token and submits without Turbo" do
    get new_dashboard_customer_commitment_path
    assert_select "form[data-turbo=false] input[name=submission_token]"
  end

  test "registers render a card per row for small screens beside the table" do
    CustomerCommitment.create!(company: @company, title: "Deliver report", customer_name: "ACME", due_date: Date.current + 7, status: "open")
    Vendor.create!(company: @company, name: "ACME Hosting")
    @company.pp_records.create!(record_type: "policy", title_en: "Leave policy")

    get dashboard_customer_commitments_path
    assert_select "ul.sm\\:hidden li", 1
    assert_select "div.hidden.sm\\:block table"
    get dashboard_vendors_path
    assert_select "ul.sm\\:hidden li", 1
    get dashboard_pp_records_path
    assert_select "ul.sm\\:hidden li", 1
  end

  test "CAPA modal selectors and dates carry accessible names" do
    capa = Capa.create!(company_id: @company.id, title: "Late audit", description: "x", status: "open", priority: "medium", created_by_id: @admin.id, source: "internal_audit")
    get dashboard_capa_management_show_path(capa)
    assert_response :success
    assert_select "select[name='capa_action[action_type]'][aria-label]"
    assert_select "select[name='capa_action[status]'][aria-label]"
    assert_select "input[name='capa_action[due_date]'][aria-label]"
    get dashboard_capa_management_list_path
    assert_select "select[name=assignee_id][aria-label]"
    assert_select "input[name=due_date_to][aria-label]"
  end
end
