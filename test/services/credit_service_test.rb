require "test_helper"
require "minitest/mock"

class CreditServiceTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(
      name: "Test Co",
      license_seats: 10,
      credits: 100,
      is_active: true
    )

    @user = User.create!(
      email: "credit-user@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "Credit User"
    )

    @company_user = CompanyUser.create!(
      company: @company,
      user: @user,
      role: CompanyUser::ROLES[:company_admin]
    )
  end

  test "set_user_credit_balance updates balances atomically" do
    CreditService.set_user_credit_balance!(@company_user, 40)

    assert_equal 40, @company_user.reload.assigned_credits
    assert_equal 60, @company.reload.credits

    CreditService.set_user_credit_balance!(@company_user, 10)

    assert_equal 10, @company_user.reload.assigned_credits
    assert_equal 90, @company.reload.credits
  end

  test "set_user_credit_balance raises when company credits are insufficient" do
    assert_raises(CreditService::InsufficientCreditsError) do
      CreditService.set_user_credit_balance!(@company_user, 150)
    end

    assert_equal 0, @company_user.reload.assigned_credits
    assert_equal 100, @company.reload.credits
  end

  test "deduct_credits consumes user credits before company pool" do
    CreditService.set_user_credit_balance!(@company_user, 20)

    CreditService.stub(:get_cost, 12) do
      assert CreditService.deduct_credits(@company, "GENERATE_CAPA_ACTIONS", company_user: @company_user)
    end

    assert_equal 8, @company_user.reload.assigned_credits
    assert_equal 80, @company.reload.credits
  end

  test "deduct_credits fails when user balance is insufficient even if company has credits" do
    CreditService.set_user_credit_balance!(@company_user, 3)
    @company.update!(credits: 50)

    CreditService.stub(:get_cost, 5) do
      refute CreditService.deduct_credits(@company, "GENERATE_CAPA_ACTIONS", company_user: @company_user)
    end

    assert_equal 3, @company_user.reload.assigned_credits
    assert_equal 50, @company.reload.credits
  end

  test "set_company_credits updates balance when value is valid" do
    CreditService.set_company_credits!(@company, 250)

    assert_equal 250, @company.reload.credits
  end

  test "set_company_credits rejects negative values" do
    assert_raises(CreditService::InvalidAssignmentError) do
      CreditService.set_company_credits!(@company, -10)
    end

    assert_equal 100, @company.reload.credits
  end
end

