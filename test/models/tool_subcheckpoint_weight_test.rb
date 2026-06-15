require "test_helper"

class ToolSubcheckpointWeightTest < ActiveSupport::TestCase
  setup do
    @tool = Tool.create!(name: "Weight Test Tool #{SecureRandom.hex(4)}", description: "Test")
    @checkpoint = ToolCheckpoint.create!(tool: @tool, name: "CP1", display_order: 1)
  end

  test "valid with nil weight (equal weight fallback)" do
    sub = ToolSubcheckpoint.new(
      tool_checkpoint: @checkpoint, name: "Sub1",
      scoring_type: "Percentage", weight: nil, is_cap: false
    )
    assert sub.valid?, sub.errors.full_messages.join(", ")
  end

  test "valid with weight at lower bound 0.0" do
    sub = ToolSubcheckpoint.new(
      tool_checkpoint: @checkpoint, name: "Sub1",
      scoring_type: "Percentage", weight: 0.0, is_cap: false
    )
    assert sub.valid?
  end

  test "valid with weight at upper bound 1.0" do
    sub = ToolSubcheckpoint.new(
      tool_checkpoint: @checkpoint, name: "Sub1",
      scoring_type: "Percentage", weight: 1.0, is_cap: false
    )
    assert sub.valid?
  end

  test "valid with weight at typical value 0.2" do
    sub = ToolSubcheckpoint.new(
      tool_checkpoint: @checkpoint, name: "Sub1",
      scoring_type: "Percentage", weight: 0.2, is_cap: false
    )
    assert sub.valid?
  end

  test "invalid with weight greater than 1.0" do
    sub = ToolSubcheckpoint.new(
      tool_checkpoint: @checkpoint, name: "Sub1",
      scoring_type: "Percentage", weight: 1.5, is_cap: false
    )
    refute sub.valid?
    assert sub.errors[:weight].any?
  end

  test "invalid with negative weight" do
    sub = ToolSubcheckpoint.new(
      tool_checkpoint: @checkpoint, name: "Sub1",
      scoring_type: "Percentage", weight: -0.1, is_cap: false
    )
    refute sub.valid?
    assert sub.errors[:weight].any?
  end

  test "is_cap defaults to false" do
    sub = ToolSubcheckpoint.create!(
      tool_checkpoint: @checkpoint, name: "Sub1",
      scoring_type: "Percentage"
    )
    assert_equal false, sub.is_cap
  end

  test "is_cap can be set to true" do
    sub = ToolSubcheckpoint.create!(
      tool_checkpoint: @checkpoint, name: "Sub1",
      scoring_type: "Percentage", is_cap: true, weight: 0.5
    )
    assert_equal true, sub.reload.is_cap
  end

  test "weight persists with decimal precision" do
    sub = ToolSubcheckpoint.create!(
      tool_checkpoint: @checkpoint, name: "Sub1",
      scoring_type: "Percentage", weight: 0.1234
    )
    assert_equal 0.1234, sub.reload.weight.to_f
  end
end
