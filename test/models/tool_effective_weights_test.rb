require "test_helper"

class ToolEffectiveWeightsTest < ActiveSupport::TestCase
  setup do
    @tool = Tool.create!(name: "EW Tool #{SecureRandom.hex(4)}", description: "Test")
    @cp1 = ToolCheckpoint.create!(tool: @tool, name: "Approach", display_order: 1)
    @cp2 = ToolCheckpoint.create!(tool: @tool, name: "Deployment", display_order: 2)
  end

  test "all_subcheckpoints returns ordered subcheckpoints across checkpoints" do
    s1 = ToolSubcheckpoint.create!(tool_checkpoint: @cp1, name: "Sound", scoring_type: "Percentage", display_order: 1)
    s2 = ToolSubcheckpoint.create!(tool_checkpoint: @cp1, name: "Aligned", scoring_type: "Percentage", display_order: 2)
    s3 = ToolSubcheckpoint.create!(tool_checkpoint: @cp2, name: "Implemented", scoring_type: "Percentage", display_order: 1)

    result = @tool.all_subcheckpoints
    assert_equal 3, result.size
    assert_equal [s1.id, s2.id, s3.id], result.map(&:id)
  end

  test "all_subcheckpoints returns empty array for tool with no checkpoints" do
    empty_tool = Tool.create!(name: "Empty Tool #{SecureRandom.hex(4)}", description: "Test")
    assert_equal [], empty_tool.all_subcheckpoints
  end

  test "effective_weights returns equal weights when all weights are null" do
    ToolSubcheckpoint.create!(tool_checkpoint: @cp1, name: "S1", scoring_type: "Percentage", weight: nil)
    ToolSubcheckpoint.create!(tool_checkpoint: @cp1, name: "S2", scoring_type: "Percentage", weight: nil)
    ToolSubcheckpoint.create!(tool_checkpoint: @cp2, name: "S3", scoring_type: "Percentage", weight: nil)

    weights = @tool.effective_weights
    assert_equal 3, weights.size
    weights.each_value do |w|
      assert_in_delta(1.0 / 3, w, 0.0001)
    end
  end

  test "effective_weights returns configured weights when set" do
    s1 = ToolSubcheckpoint.create!(tool_checkpoint: @cp1, name: "S1", scoring_type: "Percentage", weight: 0.5)
    s2 = ToolSubcheckpoint.create!(tool_checkpoint: @cp1, name: "S2", scoring_type: "Percentage", weight: 0.3)
    s3 = ToolSubcheckpoint.create!(tool_checkpoint: @cp2, name: "S3", scoring_type: "Percentage", weight: 0.2)

    weights = @tool.effective_weights
    assert_in_delta 0.5, weights[s1.id], 0.0001
    assert_in_delta 0.3, weights[s2.id], 0.0001
    assert_in_delta 0.2, weights[s3.id], 0.0001
  end

  test "effective_weights treats null weight as 0 when some weights are configured" do
    s1 = ToolSubcheckpoint.create!(tool_checkpoint: @cp1, name: "S1", scoring_type: "Percentage", weight: 0.5)
    s2 = ToolSubcheckpoint.create!(tool_checkpoint: @cp1, name: "S2", scoring_type: "Percentage", weight: nil)

    weights = @tool.effective_weights
    assert_in_delta 0.5, weights[s1.id], 0.0001
    assert_in_delta 0.0, weights[s2.id], 0.0001
  end

  test "effective_weights returns empty hash for tool with no subcheckpoints" do
    assert_equal({}, @tool.effective_weights)
  end

  test "cap_subcheckpoint_ids returns only capped subcheckpoint ids" do
    s1 = ToolSubcheckpoint.create!(tool_checkpoint: @cp1, name: "S1", scoring_type: "Percentage", is_cap: true)
    ToolSubcheckpoint.create!(tool_checkpoint: @cp1, name: "S2", scoring_type: "Percentage", is_cap: false)
    s3 = ToolSubcheckpoint.create!(tool_checkpoint: @cp2, name: "S3", scoring_type: "Percentage", is_cap: true)

    cap_ids = @tool.cap_subcheckpoint_ids
    assert_equal 2, cap_ids.size
    assert_includes cap_ids, s1.id
    assert_includes cap_ids, s3.id
  end

  test "cap_subcheckpoint_ids returns empty array when no caps" do
    ToolSubcheckpoint.create!(tool_checkpoint: @cp1, name: "S1", scoring_type: "Percentage", is_cap: false)
    assert_equal [], @tool.cap_subcheckpoint_ids
  end
end
