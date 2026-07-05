require "test_helper"

class Dashboard::CustomerCommitmentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = Company.create!(
      name: "Commitment Co #{SecureRandom.hex(4)}",
      license_seats: 5,
      is_active: true
    )

    @admin_user = User.create!(
      email: "commitment.admin.#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "Commitment Admin",
      is_active: true
    )
    CompanyUser.create!(company: @company, user: @admin_user, role: CompanyUser::ROLES[:company_admin])

    @viewer_user = User.create!(
      email: "commitment.viewer.#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "Commitment Viewer",
      is_active: true
    )
    CompanyUser.create!(company: @company, user: @viewer_user, role: CompanyUser::ROLES[:company_viewer])
  end

  test "company admin can view and create commitments" do
    sign_in @admin_user, scope: :user

    get dashboard_customer_commitments_path
    assert_response :success

    assert_difference "CustomerCommitment.count", 1 do
      post dashboard_customer_commitments_path, params: {
        customer_commitment: { title: "SLA report", customer_name: "Acme Corp" }
      }
    end
  end

  test "viewer without admin privileges is redirected" do
    sign_in @viewer_user, scope: :user

    get dashboard_customer_commitments_path

    assert_response :see_other
  end
end
