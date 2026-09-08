require "test_helper"

# The acting user is held in a thread-local so model callbacks can attribute
# changes. Puma reuses threads between requests, so failing to clear it lets one
# request's changes be recorded against the previous request's user.
class Dashboard::ActivityActorIsolationTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!

    @company = Company.create!(name: "Actor Co #{SecureRandom.hex(4)}", license_seats: 10, credits: 50, is_active: true)
    @admin = create_user("actor-admin", CompanyUser::ROLES[:company_admin])
    @viewer = create_user("actor-viewer", CompanyUser::ROLES[:company_viewer])
  end

  teardown { Thread.current[:current_user] = nil }

  def create_user(prefix, role)
    user = User.create!(email: "#{prefix}-#{SecureRandom.hex(4)}@example.com",
      password: "password123", password_confirmation: "password123", name: prefix, is_active: true)
    CompanyUser.create!(company: @company, user: user, role: role)
    user
  end

  test "a successful request leaves no actor behind" do
    sign_in @admin
    get dashboard_overview_path

    assert_response :success
    assert_nil Thread.current[:current_user]
  end

  test "a request stopped by a permission check leaves no actor behind" do
    # A before_action redirect halts the chain, which is exactly where an
    # after_action would never run.
    sign_in @viewer
    post dashboard_create_authority_path, params: { authority: { name_en: "Sneak" } }

    assert_response :redirect
    assert_nil Thread.current[:current_user],
      "a halted request must not leave its user for the next one"
  end

  test "a request for a disabled module leaves no actor behind" do
    @company.set_module!(:pp, false)

    sign_in @admin
    get dashboard_pp_records_path

    assert_response :redirect
    assert_nil Thread.current[:current_user]
  end
end
