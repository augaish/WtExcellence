require "test_helper"

class AiInstructionContextTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Ctx Co #{SecureRandom.hex(4)}", license_seats: 5, is_active: true)
  end

  test "returns nil when there are no active instructions" do
    assert_nil AiInstructionContext.for_company(@company)
  end

  test "returns nil for a nil company" do
    assert_nil AiInstructionContext.for_company(nil)
  end

  test "concatenates active instructions with titles" do
    AiInstruction.create!(company: @company, title: "Terminology", content_en: "Use KAQA terms", active: true)
    AiInstruction.create!(company: @company, title: "Ignore me", content_en: "inactive", active: false)

    context = AiInstructionContext.for_company(@company, locale: :en)

    assert_includes context, "Terminology"
    assert_includes context, "Use KAQA terms"
    refute_includes context, "inactive"
  end

  test "decorate prepends the context block to a prompt" do
    AiInstruction.create!(company: @company, title: "Rules", content_en: "Follow rule X", active: true)

    decorated = AiInstructionContext.decorate("Original prompt", company: @company, locale: :en)

    assert_includes decorated, "Company-specific context"
    assert_includes decorated, "Follow rule X"
    assert_includes decorated, "Original prompt"
  end

  test "decorate is a no-op when there are no instructions" do
    assert_equal "Just the prompt", AiInstructionContext.decorate("Just the prompt", company: @company)
  end
end
