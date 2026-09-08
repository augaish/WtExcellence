require "test_helper"

# F14 — the assistant charged credits without saying so first, while Generate
# Actions displayed its cost. A charge discovered afterwards is not one the user
# agreed to.
class Dashboard::AiCostDisclosureTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!

    @company = Company.create!(name: "Cost Co #{SecureRandom.hex(4)}", license_seats: 10, credits: 50, is_active: true)
    @admin = User.create!(email: "cost-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: "Cost Admin", is_active: true)
    CompanyUser.create!(company: @company, user: @admin, role: CompanyUser::ROLES[:company_admin])
  end

  test "the assistant states its cost before it is used" do
    cost = CreditService.get_cost("PLATFORM_ASSISTANT_QUERY")
    assert_operator cost, :>, 0, "this test is meaningless if the assistant is free"

    sign_in @admin
    get dashboard_overview_path

    assert_response :success
    assert_includes response.body, I18n.t("ai_cost.credits", count: cost)
  end
end
