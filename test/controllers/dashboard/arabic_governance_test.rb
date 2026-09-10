require "test_helper"

# Review 03, Q09: the governance registers speak Arabic when the reader does —
# status options, validation messages, error headings, weekday names.
class Dashboard::ArabicGovernanceTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!
    @company = Company.create!(name: "Ar #{SecureRandom.hex(4)}", license_seats: 10, credits: 50, is_active: true)
    @admin = User.create!(email: "ar-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: "Admin", is_active: true)
    CompanyUser.create!(company: @company, user: @admin, role: CompanyUser::ROLES[:company_admin])
    sign_in @admin
  end

  test "risk status options and a rejected closure read in Arabic" do
    get dashboard_new_risk_path(locale: :ar)
    assert_response :success
    assert_select "select[name='risk[status]'] option", text: I18n.t("risk_status.identified", locale: :ar)
    assert_select "select[name='risk[status]'] option", text: "Identified", count: 0

    risk = Risk.create!(company: @company, title: "Supplier failure", likelihood: 3, impact: 3)
    patch dashboard_update_risk_path(risk, locale: :ar), params: { risk: { status: "closed", closure_reason: "" } }
    assert_response :unprocessable_entity
    assert_select "h3", text: /يمنع الحفظ/
    assert_select "body", text: /سبب الإغلاق لا يمكن أن يكون فارغًا/
    refute_match(/can't be blank/, response.body)
  end

  test "vendor levels and commitment statuses read in Arabic" do
    get new_dashboard_vendor_path(locale: :ar)
    assert_select "select[name='vendor[risk_level]'] option", text: I18n.t("risk_level_unassessed", locale: :ar)
    get new_dashboard_customer_commitment_path(locale: :ar)
    assert_select "select[name='customer_commitment[status]'] option", text: I18n.t("commitment_status.open", locale: :ar)
  end

  test "the non-working days are named in Arabic" do
    get dashboard_general_settings_documenter_path(locale: :ar)
    assert_response :success
    assert_select "body", text: /الجمعة/
    refute_match(/Friday/, response.body)
  end
end
