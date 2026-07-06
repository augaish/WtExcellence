require "test_helper"

class Dashboard::AiInstructionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = Company.create!(name: "AI Instr Co #{SecureRandom.hex(4)}", license_seats: 5, is_active: true)

    # Custom AI Instructions are restricted to platform admins.
    @super = create_user("instr.super")
    @super.update!(role: "super_admin")

    @company_admin = create_user("instr.cadmin")
    CompanyUser.create!(company: @company, user: @company_admin, role: CompanyUser::ROLES[:company_admin])
  end

  test "platform admin can list and create instructions" do
    sign_in @super, scope: :user

    get dashboard_ai_instructions_path
    assert_response :success

    assert_difference "AiInstruction.count", 1 do
      post dashboard_ai_instructions_path, params: {
        ai_instruction: { title: "Terminology", content_en: "Use KAQA terms", active: "1" }
      }
    end
    assert_redirected_to dashboard_ai_instructions_path
  end

  test "invalid instruction (no content) is rejected" do
    sign_in @super, scope: :user

    assert_no_difference "AiInstruction.count" do
      post dashboard_ai_instructions_path, params: { ai_instruction: { title: "Empty" } }
    end
    assert_response :unprocessable_entity
  end

  test "toggle flips active" do
    sign_in @super, scope: :user
    instruction = AiInstruction.create!(company: @company, title: "T", content_en: "x", active: true)

    patch toggle_dashboard_ai_instruction_path(instruction)

    refute instruction.reload.active
  end

  test "company admin is denied (platform admins only)" do
    sign_in @company_admin, scope: :user

    get dashboard_ai_instructions_path

    assert_response :see_other
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
