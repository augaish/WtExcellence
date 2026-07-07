require "test_helper"

class Dashboard::DashboardLayoutsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = Company.create!(
      name: "Layout Co #{SecureRandom.hex(4)}",
      license_seats: 5,
      is_active: true
    )

    @admin_user = User.create!(
      email: "layout.admin.#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "Layout Admin",
      is_active: true
    )
    CompanyUser.create!(company: @company, user: @admin_user, role: CompanyUser::ROLES[:company_admin])

    @viewer_user = User.create!(
      email: "layout.viewer.#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "Layout Viewer",
      is_active: true
    )
    CompanyUser.create!(company: @company, user: @viewer_user, role: CompanyUser::ROLES[:company_viewer])
  end

  test "overview renders for company admin with customize controls" do
    sign_in @admin_user, scope: :user
    get dashboard_overview_path
    assert_response :success
  end

  test "overview renders for super admin (platform-wide governance rollup)" do
    super_admin = User.create!(
      email: "layout.super.#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "Layout Super",
      role: "super_admin",
      is_active: true
    )
    sign_in super_admin, scope: :user
    get dashboard_overview_path
    assert_response :success
  end

  test "super admin saves layouts under the platform scope" do
    super_admin = User.create!(
      email: "layout.super2.#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "Layout Super 2",
      role: "super_admin",
      is_active: true
    )
    sign_in super_admin, scope: :user

    patch dashboard_overview_layout_path, params: {
      slot: 1,
      order: %w[governance top_metrics second_metrics charts tables],
      hidden: []
    }, as: :json
    assert_response :success

    layout = DashboardLayout.platform.find_by(slot: 1)
    assert_not_nil layout
    assert_nil layout.company_id
    assert_equal 1, DashboardLayout.active_slot(scope: "platform", company_id: nil)
  end

  test "admin can save a layout with order and hidden widgets" do
    sign_in @admin_user, scope: :user

    patch dashboard_overview_layout_path, params: {
      slot: 2,
      order: %w[governance top_metrics second_metrics charts tables],
      hidden: %w[tables]
    }, as: :json

    assert_response :success

    layout = DashboardLayout.for_company(@company.id).find_by(slot: 2)
    assert_not_nil layout
    # Saved order is honoured first, then any not-yet-placed widgets are backfilled.
    assert_equal %w[governance top_metrics second_metrics charts tables], layout.ordered_widgets.first(5)
    assert_equal DashboardLayout::WIDGET_KEYS.sort, layout.ordered_widgets.sort
    assert_equal %w[tables], layout.hidden_widgets
    assert layout.is_active, "saved slot should become active"
    assert_equal 2, DashboardLayout.active_slot(scope: "company", company_id: @company.id)
  end

  test "save ignores unknown widget keys" do
    sign_in @admin_user, scope: :user

    patch dashboard_overview_layout_path, params: {
      slot: 1,
      order: %w[governance evil_widget top_metrics],
      hidden: %w[../../etc/passwd]
    }, as: :json

    assert_response :success
    layout = DashboardLayout.for_company(@company.id).find_by(slot: 1)
    # Unknown keys dropped; known saved keys kept first, rest backfilled.
    assert_equal %w[governance top_metrics], layout.ordered_widgets.first(2)
    assert_equal DashboardLayout::WIDGET_KEYS.sort, layout.ordered_widgets.sort
    assert_empty layout.hidden_widgets
  end

  test "admin can activate a different slot" do
    sign_in @admin_user, scope: :user

    post dashboard_activate_overview_layout_path, params: { slot: 3 }
    assert_response :see_other
    assert_equal 3, DashboardLayout.active_slot(scope: "company", company_id: @company.id)
  end

  test "non-admin cannot save layouts" do
    sign_in @viewer_user, scope: :user

    patch dashboard_overview_layout_path, params: { slot: 1, order: %w[governance], hidden: [] }, as: :json
    assert_response :see_other
    assert_nil DashboardLayout.for_company(@company.id).find_by(slot: 1)
  end
end
