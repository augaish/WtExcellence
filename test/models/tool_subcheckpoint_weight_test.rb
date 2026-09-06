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
      scoring_type: "Percentage", weight: 100, is_cap: false
    )
    assert sub.valid?
  end

  test "valid with weight at typical value 0.2" do
    sub = ToolSubcheckpoint.new(
      tool_checkpoint: @checkpoint, name: "Sub1",
      scoring_type: "Percentage", weight: 20, is_cap: false
    )
    assert sub.valid?
  end

  test "invalid with weight greater than 100" do
    sub = ToolSubcheckpoint.new(
      tool_checkpoint: @checkpoint, name: "Sub1",
      scoring_type: "Percentage", weight: 150, is_cap: false
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
      scoring_type: "Percentage", is_cap: true, weight: 50
    )
    assert_equal true, sub.reload.is_cap
  end

  # The column is decimal(5,2): percentages keep two decimal places, so 12.34
  # round-trips exactly and anything finer is rounded to the stored scale.
  test "weight persists with two decimal places" do
    sub = ToolSubcheckpoint.create!(
      tool_checkpoint: @checkpoint, name: "Sub1",
      scoring_type: "Percentage", weight: 12.34
    )
    assert_equal 12.34, sub.reload.weight.to_f
  end

  test "weight is rounded to the stored scale" do
    sub = ToolSubcheckpoint.create!(
      tool_checkpoint: @checkpoint, name: "Sub2",
      scoring_type: "Percentage", weight: 12.3456
    )
    assert_equal 12.35, sub.reload.weight.to_f
  end
end
