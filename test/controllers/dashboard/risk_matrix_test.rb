require "test_helper"

# F19 — the Overview and the Register drew the axes the opposite way round, and
# the matrix silently counted a different population from the summary beside it.
class Dashboard::RiskMatrixTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!

    @company = Company.create!(name: "Matrix Co #{SecureRandom.hex(4)}", license_seats: 10, credits: 50, is_active: true)
    @admin = User.create!(email: "matrix-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: "Matrix Admin", is_active: true)
    CompanyUser.create!(company: @company, user: @admin, role: CompanyUser::ROLES[:company_admin])

    @open_risk = @company.risks.create!(title: "Open risk", likelihood: 4, impact: 2)
    @closed_risk = @company.risks.create!(title: "Closed risk", likelihood: 1, impact: 1,
      status: "closed", closure_reason: "Mitigated.")
  end

  test "the register draws likelihood vertically and impact horizontally" do
    sign_in @admin
    get dashboard_risk_management_index_path

    assert_response :success
    # The row label is likelihood; the column label is impact.
    assert_select "td", text: /#{I18n.t('likelihood', default: 'Likelihood')} 5/
    assert_select "td", text: /#{I18n.t('impact', default: 'Impact')} 5/
  end

  test "the matrix says which risks it is counting" do
    sign_in @admin
    get dashboard_risk_management_index_path

    assert_includes response.body, I18n.t("risk_matrix_population.open", count: 1)
  end

  test "closed risks are excluded by default and included on request" do
    sign_in @admin

    get dashboard_risk_management_index_path
    assert_includes response.body, I18n.t("risk_matrix_population.open", count: 1)

    get dashboard_risk_management_index_path(population: "all")
    assert_includes response.body, I18n.t("risk_matrix_population.all", count: 2)
  end

  test "a cell counts risks in the singular and the plural correctly" do
    @company.risks.create!(title: "Second open risk", likelihood: 4, impact: 2)

    sign_in @admin
    get dashboard_risk_management_index_path

    assert_includes response.body, I18n.t("risks_count", count: 2)
    assert_not_includes response.body, "1 risks"
  end
end
