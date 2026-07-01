require "test_helper"

class Dashboard::VendorsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = Company.create!(
      name: "Vendor Co #{SecureRandom.hex(4)}",
      license_seats: 5,
      is_active: true
    )

    @admin_user = User.create!(
      email: "vendor.admin.#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "Vendor Admin",
      is_active: true
    )
    CompanyUser.create!(company: @company, user: @admin_user, role: CompanyUser::ROLES[:company_admin])

    @viewer_user = User.create!(
      email: "vendor.viewer.#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "Vendor Viewer",
      is_active: true
    )
    CompanyUser.create!(company: @company, user: @viewer_user, role: CompanyUser::ROLES[:company_viewer])
  end

  test "company admin can view and create vendors" do
    sign_in @admin_user, scope: :user

    get dashboard_vendors_path
    assert_response :success

    assert_difference "Vendor.count", 1 do
      post dashboard_vendors_path, params: { vendor: { name: "Cloud Host Inc" } }
    end
  end

  test "viewer without admin privileges is redirected" do
    sign_in @viewer_user, scope: :user

    get dashboard_vendors_path

    assert_response :forbidden
  end
end
