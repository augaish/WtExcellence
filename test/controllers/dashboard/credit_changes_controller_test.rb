require "test_helper"

class Dashboard::CreditChangesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @super_admin = User.create!(
      email: "super.admin@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "Super Admin",
      role: "super_admin",
      is_active: true
    )

    @regular_user = User.create!(
      email: "regular.user@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "Regular User",
      is_active: true
    )

    @company = Company.create!(
      name: "Credits Co",
      license_seats: 5,
      credits: 100,
      is_active: true,
      default_locale: "en"
    )

    @company_member = User.create!(
      email: "member@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "Credits Member"
    )

    @company_user = CompanyUser.create!(
      company: @company,
      user: @company_member,
      role: CompanyUser::ROLES[:company_admin],
      assigned_credits: 10
    )
  end

  test "super admin can update company credits via json" do
    sign_in @super_admin, scope: :user

    patch dashboard_credit_changes_company_path(@company), params: { credits: 750 }, as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["success"]
    assert_equal 750, @company.reload.credits
  end

  test "update_company rejects negative credit amounts" do
    sign_in @super_admin, scope: :user

    patch dashboard_credit_changes_company_path(@company), params: { credits: -5 }, as: :json

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal false, body["success"]
    assert_equal 100, @company.reload.credits
  end

  test "non super admin is rejected from update_company" do
    sign_in @regular_user, scope: :user

    patch dashboard_credit_changes_company_path(@company), params: { credits: 200 }, as: :json

    assert_response :forbidden
    assert_equal 100, @company.reload.credits
  end

  test "super admin can load company users as json" do
    sign_in @super_admin, scope: :user

    get dashboard_credit_changes_company_users_path(@company), as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["success"]
    user = body["users"].find { |u| u["id"] == @company_user.id }
    refute_nil user
    assert_equal 10, user["assigned_credits"]
  end

  test "super admin can update company user credits" do
    sign_in @super_admin, scope: :user

    patch dashboard_credit_changes_company_user_path(@company, @company_user),
          params: { assigned_credits: 25 },
          as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["success"]
    assert_equal 25, body.dig("user", "assigned_credits")
    assert_equal 25, @company_user.reload.assigned_credits
    assert_equal 85, @company.reload.credits
  end

  test "update_company_user rejects negative amounts" do
    sign_in @super_admin, scope: :user

    patch dashboard_credit_changes_company_user_path(@company, @company_user),
          params: { assigned_credits: -1 },
          as: :json

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal false, body["success"]
    assert_equal 10, @company_user.reload.assigned_credits
    assert_equal 100, @company.reload.credits
  end

  test "non super admin cannot update company user credits" do
    sign_in @regular_user, scope: :user

    patch dashboard_credit_changes_company_user_path(@company, @company_user),
          params: { assigned_credits: 50 },
          as: :json

    assert_response :forbidden
    assert_equal 10, @company_user.reload.assigned_credits
  end
end

