require "test_helper"

class Dashboard::OverviewWorkQueueTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!
    @company = Company.create!(name: "OV #{SecureRandom.hex(4)}", license_seats: 10, credits: 50, is_active: true)
    @admin = User.create!(email: "ov-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: "Admin", is_active: true)
    @cu = CompanyUser.create!(company: @company, user: @admin, role: CompanyUser::ROLES[:company_admin])
  end

  test "the overview opens with what needs me and, for an admin of a new company, the setup checklist" do
    CustomerCommitment.create!(company: @company, title: "Late report", customer_name: "Bank", due_date: Date.current - 1, owner: @cu)
    sign_in @admin
    get dashboard_overview_path
    assert_response :success
    assert_select "h2", text: I18n.t("work_queue.title")
    assert_select "a", text: "Late report"
    assert_select "h2", text: I18n.t("setup_checklist.title")
    assert_select "a", text: I18n.t("setup_checklist.steps.branding")
  end
end
