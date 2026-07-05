require "test_helper"
require "minitest/mock"

class Dashboard::AiAssistantControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = Company.create!(
      name: "AI Co #{SecureRandom.hex(4)}",
      license_seats: 5,
      credits: 100,
      is_active: true
    )

    @admin = create_user("ai.admin")
    CompanyUser.create!(company: @company, user: @admin, role: CompanyUser::ROLES[:company_admin], assigned_credits: 20)

    @contributor = create_user("ai.contrib")
    CompanyUser.create!(company: @company, user: @contributor, role: CompanyUser::ROLES[:company_contributor], assigned_credits: 20)

    @risk_manager = create_user("ai.risk")
    CompanyUser.create!(company: @company, user: @risk_manager, role: CompanyUser::ROLES[:company_risk_manager], assigned_credits: 20)
  end

  test "blank question is rejected" do
    sign_in @admin, scope: :user

    post dashboard_ai_assistant_ask_path, params: { question: "  " }, as: :json

    assert_response :unprocessable_entity
  end

  test "contributor has no access" do
    sign_in @contributor, scope: :user

    post dashboard_ai_assistant_ask_path, params: { question: "hello" }, as: :json

    assert_response :forbidden
  end

  test "risk manager is blocked" do
    sign_in @risk_manager, scope: :user

    post dashboard_ai_assistant_ask_path, params: { question: "hello" }, as: :json

    assert_response :forbidden
  end

  test "successful query deducts credits" do
    sign_in @admin, scope: :user
    company_user = @admin.company_user
    fake = Struct.new(:result) do
      def ask(_q) = { answer: "ok", sources: [] }
    end.new(nil)

    assert_difference -> { company_user.reload.assigned_credits }, -2 do
      PlatformAssistantService.stub(:new, fake) do
        post dashboard_ai_assistant_ask_path, params: { question: "status?" }, as: :json
      end
    end

    assert_response :success
    assert JSON.parse(@response.body)["success"]
  end

  test "LLM failure does not deduct credits" do
    sign_in @admin, scope: :user
    company_user = @admin.company_user
    failing = Object.new
    def failing.ask(_q) = raise(PlatformAssistantService::AssistantError, "down")

    assert_no_difference -> { company_user.reload.assigned_credits } do
      PlatformAssistantService.stub(:new, failing) do
        post dashboard_ai_assistant_ask_path, params: { question: "status?" }, as: :json
      end
    end

    assert_response :bad_gateway
  end

  private

  def create_user(prefix)
    User.create!(
      email: "#{prefix}.#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: prefix,
      is_active: true
    )
  end
end
