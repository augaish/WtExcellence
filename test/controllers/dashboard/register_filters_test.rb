require "test_helper"

class Dashboard::RegisterFiltersTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!

    @company = Company.create!(name: "Reg Co #{SecureRandom.hex(4)}", license_seats: 10, credits: 50, is_active: true)
    @admin = User.create!(email: "reg-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: "Reg Admin", is_active: true)
    @membership = CompanyUser.create!(company: @company, user: @admin, role: CompanyUser::ROLES[:company_admin])
  end

  test "each register offers search and its own work queues" do
    { dashboard_risk_management_index_path => %w[all mine open above_appetite closed],
      dashboard_vendors_path => %w[all mine unassessed critical],
      dashboard_customer_commitments_path => %w[all mine overdue due_soon fulfilled] }.each do |path, queues|
      sign_in @admin
      get path

      assert_response :success, "#{path} failed to render"
      assert_select "input[name=?]", "q"
      queues.each do |queue|
        assert_includes response.body, I18n.t("registers.queues.#{queue}"),
          "#{path} is missing the #{queue} queue"
      end
    end
  end

  test "a search narrows the register and says how many it is showing" do
    @company.risks.create!(title: "Supplier outage", likelihood: 3, impact: 3)
    @company.risks.create!(title: "Data loss", likelihood: 2, impact: 2)

    sign_in @admin
    get dashboard_risk_management_index_path(q: "supplier")

    assert_response :success
    assert_includes response.body, I18n.t("registers.showing", count: 1, total: 2)
    assert_includes response.body, "Supplier outage"
    assert_not_includes response.body, "Data loss"
  end

  test "the matrix keeps describing the whole register while a search is active" do
    @company.risks.create!(title: "Supplier outage", likelihood: 3, impact: 3)
    @company.risks.create!(title: "Data loss", likelihood: 2, impact: 2)

    sign_in @admin
    get dashboard_risk_management_index_path(q: "supplier")

    # A heatmap of filtered results would invite the wrong conclusion.
    assert_includes response.body, I18n.t("risk_matrix_population.open", count: 2)
  end

  test "the mine queue reaches what the signed-in manager owns" do
    mine = @company.vendors.create!(name: "My vendor", owner: @membership)
    @company.vendors.create!(name: "Someone else's vendor")

    sign_in @admin
    get dashboard_vendors_path(queue: "mine")

    assert_response :success
    assert_includes response.body, mine.name
    assert_not_includes response.body, "Someone else's vendor"
  end

  test "clearing is offered only while a filter is active" do
    sign_in @admin

    get dashboard_customer_commitments_path
    assert_not_includes response.body, I18n.t("registers.clear")

    get dashboard_customer_commitments_path(queue: "overdue")
    assert_includes response.body, I18n.t("registers.clear")
  end
end
