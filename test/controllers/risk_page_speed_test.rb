require "test_helper"

# The risk pages stay within a fixed number of queries however many risks exist.
class RiskPageSpeedTest < ActionDispatch::IntegrationTest
  test "the risk list and a risk page do not grow queries with the number of risks" do
    Rails.application.reload_routes!
    company = Company.create!(name: "Speed #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    rm = User.create!(email: "speed-#{SecureRandom.hex(4)}@example.com", password: "Password1234", password_confirmation: "Password1234", name: "RM", is_active: true)
    cu = CompanyUser.create!(company: company, user: rm, role: CompanyUser::ROLES[:company_risk_manager])
    make = ->(n) { n.times { |i| Risk.create!(company: company, title: "R#{SecureRandom.hex(3)}", cause: "c", event: "e", impact_statement: "i", likelihood: 3, impact: 3, status: "identified", owner: cu, created_by: rm) } }
    count = lambda do |path|
      n = 0
      cb = ->(*, payload) { n += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
      ActiveSupport::Notifications.subscribed(cb, "sql.active_record") { get path }
      n
    end

    make.call(5)
    sign_in rm
    get dashboard_risk_management_index_path
    few_index = count.call(dashboard_risk_management_index_path)
    few_show = count.call(dashboard_risk_management_path(Risk.last))
    make.call(40)
    many_index = count.call(dashboard_risk_management_index_path)
    many_show = count.call(dashboard_risk_management_path(Risk.last))

    assert_operator many_index - few_index, :<=, 3, "risk list: #{few_index} → #{many_index} queries"
    assert_operator many_show - few_show, :<=, 3, "risk page: #{few_show} → #{many_show} queries"
    assert_operator many_show, :<, 50
  end
end
