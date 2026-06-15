require "test_helper"

class CompanyUserTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(
      name: "Validator Co",
      license_seats: 5,
      credits: 100,
      is_active: true
    )

    @user = User.create!(
      email: "validator@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "Validator User"
    )
  end

  test "assigned credits default to zero" do
    company_user = CompanyUser.create!(
      company: @company,
      user: @user,
      role: CompanyUser::ROLES[:company_admin]
    )

    assert_equal 0, company_user.assigned_credits
    assert_equal 0, company_user.credit_balance
  end

  test "assigned credits cannot be negative" do
    company_user = CompanyUser.new(
      company: @company,
      user: @user,
      role: CompanyUser::ROLES[:company_admin],
      assigned_credits: -5
    )

    refute company_user.valid?
    assert_includes company_user.errors[:assigned_credits], "must be greater than or equal to 0"
  end
end
