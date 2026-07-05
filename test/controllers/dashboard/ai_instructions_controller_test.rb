require "test_helper"

class Dashboard::AiInstructionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = Company.create!(name: "AI Instr Co #{SecureRandom.hex(4)}", license_seats: 5, is_active: true)

    @admin = create_user("instr.admin")
    CompanyUser.create!(company: @company, user: @admin, role: CompanyUser::ROLES[:company_admin])

    @viewer = create_user("instr.viewer")
    CompanyUser.create!(company: @company, user: @viewer, role: CompanyUser::ROLES[:company_viewer])
  end

  test "admin can list and create instructions" do
    sign_in @admin, scope: :user

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
    sign_in @admin, scope: :user

    assert_no_difference "AiInstruction.count" do
      post dashboard_ai_instructions_path, params: { ai_instruction: { title: "Empty" } }
    end
    assert_response :unprocessable_entity
  end

  test "toggle flips active" do
    sign_in @admin, scope: :user
    instruction = AiInstruction.create!(company: @company, title: "T", content_en: "x", active: true)

    patch toggle_dashboard_ai_instruction_path(instruction)

    refute instruction.reload.active
  end

  test "viewer without admin privileges is redirected" do
    sign_in @viewer, scope: :user

    get dashboard_ai_instructions_path

    assert_response :see_other
  end

  test "cannot access another company's instruction" do
    other = Company.create!(name: "Other #{SecureRandom.hex(4)}", license_seats: 5, is_active: true)
    foreign = AiInstruction.create!(company: other, title: "Foreign", content_en: "secret", active: true)

    sign_in @admin, scope: :user

    get edit_dashboard_ai_instruction_path(foreign)

    assert_response :not_found
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
