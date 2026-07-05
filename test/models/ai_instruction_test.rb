require "test_helper"

class AiInstructionTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "AI Instr Co #{SecureRandom.hex(4)}", license_seats: 5, is_active: true)
  end

  test "requires a title" do
    instruction = AiInstruction.new(company: @company, content_en: "hello")

    refute instruction.valid?
    assert_includes instruction.errors[:title], "can't be blank"
  end

  test "requires content in at least one language" do
    instruction = AiInstruction.new(company: @company, title: "Terminology")

    refute instruction.valid?
    assert instruction.errors[:base].any?
  end

  test "valid with only Arabic content" do
    instruction = AiInstruction.new(company: @company, title: "Terminology", content_ar: "مصطلحات")

    assert instruction.valid?
  end

  test "content_for falls back to the other language" do
    instruction = AiInstruction.create!(company: @company, title: "T", content_en: "English only")

    assert_equal "English only", instruction.content_for(:ar)
    assert_equal "English only", instruction.content_for(:en)
  end

  test "active scope excludes inactive and soft-deleted" do
    keep = AiInstruction.create!(company: @company, title: "A", content_en: "x", active: true)
    AiInstruction.create!(company: @company, title: "B", content_en: "y", active: false)
    deleted = AiInstruction.create!(company: @company, title: "C", content_en: "z", active: true)
    deleted.soft_delete!

    ids = AiInstruction.active.where(company: @company).pluck(:id)
    assert_includes ids, keep.id
    assert_equal 1, ids.size
  end
end
