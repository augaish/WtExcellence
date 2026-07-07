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

  test "admin can raise a linked CAPA from a commitment" do
    sign_in @admin_user, scope: :user
    commitment = CustomerCommitment.create!(company: @company, title: "SLA report", customer_name: "Acme Corp")

    assert_difference "Capa.count", 1 do
      post create_capa_dashboard_customer_commitment_path(commitment)
    end

    capa = Capa.order(:created_at).last
    assert_equal commitment, capa.origin
    assert_redirected_to dashboard_capa_management_show_path(capa)
  end

  test "show page renders the linked CAPAs section" do
    sign_in @admin_user, scope: :user
    commitment = CustomerCommitment.create!(company: @company, title: "SLA report", customer_name: "Acme Corp")

    get dashboard_customer_commitment_path(commitment)
    assert_response :success
    assert_match I18n.t("linked_capas"), @response.body
  end

  test "viewer cannot raise a CAPA" do
    sign_in @viewer_user, scope: :user
    commitment = CustomerCommitment.create!(company: @company, title: "SLA report", customer_name: "Acme Corp")

    assert_no_difference "Capa.count" do
      post create_capa_dashboard_customer_commitment_path(commitment)
    end
    assert_response :see_other
  end
end
