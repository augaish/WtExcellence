require "test_helper"

class ClauseScoreCalculatorTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Score Test Co #{SecureRandom.hex(4)}", license_seats: 10, credits: 100, is_active: true)

    @standard = Standard.create!(code: "EFQM-#{SecureRandom.hex(4)}")
    @version = StandardVersion.create!(standard: @standard, version_label: "2020", status: "published")

    @parent_clause = Clause.create!(standard_version: @version, code: "1", sort_order: 0)
    @clause = Clause.create!(standard_version: @version, code: "1.1", sort_order: 0, parent: @parent_clause, allocated_points: 100)

    @tool = Tool.create!(name: "EFQM Tool #{SecureRandom.hex(4)}", description: "Test EFQM Tool")

    # Create EFQM-like structure: 3 checkpoints, 6 subcheckpoints
    @cp_approach = ToolCheckpoint.create!(tool: @tool, name: "Approach", display_order: 1)
    @cp_deployment = ToolCheckpoint.create!(tool: @tool, name: "Deployment", display_order: 2)
    @cp_assessment = ToolCheckpoint.create!(tool: @tool, name: "Assessment", display_order: 3)

    @sound = ToolSubcheckpoint.create!(tool_checkpoint: @cp_approach, name: "Sound", scoring_type: "Percentage", weight: 0.2, is_cap: true, display_order: 1)
    @aligned = ToolSubcheckpoint.create!(tool_checkpoint: @cp_approach, name: "Aligned", scoring_type: "Percentage", weight: 0.2, is_cap: false, display_order: 2)
    @implemented = ToolSubcheckpoint.create!(tool_checkpoint: @cp_deployment, name: "Implemented", scoring_type: "Percentage", weight: 0.2, is_cap: false, display_order: 1)
    @flexible = ToolSubcheckpoint.create!(tool_checkpoint: @cp_deployment, name: "Flexible", scoring_type: "Percentage", weight: 0.2, is_cap: false, display_order: 2)
    @evaluated = ToolSubcheckpoint.create!(tool_checkpoint: @cp_assessment, name: "Evaluated", scoring_type: "Percentage", weight: 0.1, is_cap: false, display_order: 1)
    @learn = ToolSubcheckpoint.create!(tool_checkpoint: @cp_assessment, name: "Learn", scoring_type: "Percentage", weight: 0.1, is_cap: false, display_order: 2)

    @tool_clause = ToolClause.create!(tool: @tool, clause: @clause)
  end

  # --- AC-D1: Weighted sum calculation ---

  test "weighted sum is correct: SUM(score_i * weight_i)" do
    # Sound=65 (0.2), Aligned=70 (0.2), Implemented=55 (0.2), Flexible=60 (0.2), Evaluated=50 (0.1), Learn=45 (0.1)
    # weighted_sum = 65*0.2 + 70*0.2 + 55*0.2 + 60*0.2 + 50*0.1 + 45*0.1 = 13+14+11+12+5+4.5 = 59.5
    create_assignment(@sound, 65)
    create_assignment(@aligned, 70)
    create_assignment(@implemented, 55)
    create_assignment(@flexible, 60)
    create_assignment(@evaluated, 50)
    create_assignment(@learn, 45)

    result = ClauseScoreCalculator.new(@tool_clause).calculate_score(@company)

    assert_in_delta 59.5, result[:weighted_sum], 0.01
  end

  # --- AC-D2: Cap applied when weighted_sum > cap_value ---

  test "cap is applied: Sound (cap)=65, weighted_sum=70 -> overall=65" do
    # Set all non-cap attributes high enough to produce weighted_sum > 65
    create_assignment(@sound, 65) # cap attribute
    create_assignment(@aligned, 80)
    create_assignment(@implemented, 80)
    create_assignment(@flexible, 80)
    create_assignment(@evaluated, 80)
    create_assignment(@learn, 80)

    # weighted_sum = 65*0.2 + 80*0.2 + 80*0.2 + 80*0.2 + 80*0.1 + 80*0.1 = 13+16+16+16+8+8 = 77
    result = ClauseScoreCalculator.new(@tool_clause).calculate_score(@company)

    assert result[:cap_applied], "Cap should be applied"
    assert_in_delta 65.0, result[:percentage], 0.01
    assert_equal "Sound", result[:cap_attribute]
  end

  # --- AC-D3: Multiple caps use MIN ---

  test "multiple caps: Sound(cap)=60, Implemented(cap)=50 -> overall capped at 50" do
    @implemented.update!(is_cap: true)
    create_assignment(@sound, 60)
    create_assignment(@aligned, 100)
    create_assignment(@implemented, 50)
    create_assignment(@flexible, 100)
    create_assignment(@evaluated, 100)
    create_assignment(@learn, 100)

    # weighted_sum = 60*0.2 + 100*0.2 + 50*0.2 + 100*0.2 + 100*0.1 + 100*0.1 = 12+20+10+20+10+10 = 82
    # cap = MIN(60, 50) = 50
    result = ClauseScoreCalculator.new(@tool_clause).calculate_score(@company)

    assert result[:cap_applied]
    assert_in_delta 50.0, result[:percentage], 0.01
    assert_equal "Implemented", result[:cap_attribute]
  end

  # --- AC-D4: Cap at 0 -> Overall = 0 ---

  test "cap at 0: Sound(cap)=0 -> overall=0 regardless of other scores" do
    create_assignment(@sound, 0) # cap = 0
    create_assignment(@aligned, 100)
    create_assignment(@implemented, 100)
    create_assignment(@flexible, 100)
    create_assignment(@evaluated, 100)
    create_assignment(@learn, 100)

    result = ClauseScoreCalculator.new(@tool_clause).calculate_score(@company)

    assert result[:cap_applied]
    assert_in_delta 0.0, result[:percentage], 0.01
  end

  # --- AC-D5: No weights configured -> equal weighting fallback ---

  test "no weights configured: equal weighting fallback (1/N)" do
    # Remove all weights
    [@sound, @aligned, @implemented, @flexible, @evaluated, @learn].each { |s| s.update!(weight: nil, is_cap: false) }

    create_assignment(@sound, 100)
    create_assignment(@aligned, 50)
    create_assignment(@implemented, 100)
    create_assignment(@flexible, 50)
    create_assignment(@evaluated, 100)
    create_assignment(@learn, 50)

    # equal weight = 1/6
    # weighted_sum = (100+50+100+50+100+50) * (1/6) = 450/6 = 75
    result = ClauseScoreCalculator.new(@tool_clause).calculate_score(@company)

    assert_in_delta 75.0, result[:percentage], 0.01
  end

  # --- AC-D6: No caps configured -> overall = weighted_sum ---

  test "no caps configured: overall equals weighted_sum exactly" do
    @sound.update!(is_cap: false) # Remove the cap

    create_assignment(@sound, 65)
    create_assignment(@aligned, 70)
    create_assignment(@implemented, 55)
    create_assignment(@flexible, 60)
    create_assignment(@evaluated, 50)
    create_assignment(@learn, 45)

    result = ClauseScoreCalculator.new(@tool_clause).calculate_score(@company)

    assert_equal false, result[:cap_applied]
    assert_in_delta 59.5, result[:percentage], 0.01
    assert_equal result[:weighted_sum], result[:percentage]
  end

  # --- AC-D7: Score propagation (cache is updated) ---

  test "score propagation updates parent clause cache" do
    create_assignment(@sound, 65)
    create_assignment(@aligned, 70)
    create_assignment(@implemented, 55)
    create_assignment(@flexible, 60)
    create_assignment(@evaluated, 50)
    create_assignment(@learn, 45)

    # Propagate
    ClauseScorePropagator.propagate_from_terminal_clause(@clause, @company)

    cache = ClauseScoreCache.find_by(clause_id: @clause.id, company_id: @company.id)
    assert cache.present?, "Cache should be created"
    assert cache.cached_percentage.present?, "cached_percentage should be set"
    assert_in_delta 59.5, cache.cached_percentage.to_f, 0.5
  end

  # --- AC-D8: Cap violation recorded in cache ---

  test "cap violation recorded in cache business_rule_violation" do
    create_assignment(@sound, 20) # cap attribute
    create_assignment(@aligned, 100)
    create_assignment(@implemented, 100)
    create_assignment(@flexible, 100)
    create_assignment(@evaluated, 100)
    create_assignment(@learn, 100)

    result = ClauseScoreCalculator.new(@tool_clause).calculate_score(@company)

    assert result[:cap_applied]
    assert_includes result[:business_rule_violation], "Sound"
    assert_includes result[:business_rule_violation], "capped"
  end

  # --- AC-D9: Final score formula ---

  test "final score = allocated_points * (overall / 100)" do
    @sound.update!(is_cap: false)

    create_assignment(@sound, 62)
    create_assignment(@aligned, 62)
    create_assignment(@implemented, 62)
    create_assignment(@flexible, 62)
    create_assignment(@evaluated, 62)
    create_assignment(@learn, 62)

    # All attributes = 62, all weights sum to 1.0 -> overall = 62%
    # final_score = 100 * (62/100) = 62.0
    result = ClauseScoreCalculator.new(@tool_clause).calculate_score(@company)

    assert_in_delta 62.0, result[:percentage], 0.01
    assert_in_delta 62.0, result[:score], 0.01
    assert_equal 100, result[:allocated_points]
  end

  # --- AC-D10: Scores are company-scoped ---

  test "scores are company-scoped: different companies see independent scores" do
    company_b = Company.create!(name: "Company B #{SecureRandom.hex(4)}", license_seats: 10, credits: 50, is_active: true)

    # Company A scores
    create_assignment(@sound, 80)
    create_assignment(@aligned, 80)
    create_assignment(@implemented, 80)
    create_assignment(@flexible, 80)
    create_assignment(@evaluated, 80)
    create_assignment(@learn, 80)

    # Company B scores (lower)
    create_assignment(@sound, 20, company_b)
    create_assignment(@aligned, 20, company_b)
    create_assignment(@implemented, 20, company_b)
    create_assignment(@flexible, 20, company_b)
    create_assignment(@evaluated, 20, company_b)
    create_assignment(@learn, 20, company_b)

    result_a = ClauseScoreCalculator.new(@tool_clause).calculate_score(@company)
    result_b = ClauseScoreCalculator.new(@tool_clause).calculate_score(company_b)

    # Company A: Sound(cap)=80, weighted_sum=80 -> overall=80
    assert_in_delta 80.0, result_a[:weighted_sum], 0.01

    # Company B: Sound(cap)=20, weighted_sum=20 -> overall=20
    assert_in_delta 20.0, result_b[:weighted_sum], 0.01

    refute_equal result_a[:percentage], result_b[:percentage]
  end

  # --- Edge cases ---

  test "no scores entered yet: overall = 0" do
    result = ClauseScoreCalculator.new(@tool_clause).calculate_score(@company)

    assert_equal 0, result[:evaluated_count]
    assert_in_delta 0.0, result[:percentage], 0.01
  end

  test "only some attributes scored: unscored treated as 0" do
    create_assignment(@sound, 100) # only one scored

    result = ClauseScoreCalculator.new(@tool_clause).calculate_score(@company)

    # weighted_sum = 100*0.2 + 0*0.2 + 0*0.2 + 0*0.2 + 0*0.1 + 0*0.1 = 20
    # cap(Sound) = 100 -> no cap applied
    assert_in_delta 20.0, result[:weighted_sum], 0.01
    assert_equal 1, result[:evaluated_count]
  end

  test "tool with no subcheckpoints returns zero result" do
    empty_tool = Tool.create!(name: "Empty #{SecureRandom.hex(4)}", description: "Test")
    empty_clause = Clause.create!(standard_version: @version, code: "2.1", sort_order: 1, allocated_points: 50)
    empty_tc = ToolClause.create!(tool: empty_tool, clause: empty_clause)

    result = ClauseScoreCalculator.new(empty_tc).calculate_score(@company)

    assert_equal 0, result[:score]
    assert_equal 0, result[:percentage]
    assert_equal 0, result[:total_count]
  end

  test "cap not applied when weighted_sum does not exceed cap value" do
    create_assignment(@sound, 80) # cap attribute = 80
    create_assignment(@aligned, 30)
    create_assignment(@implemented, 30)
    create_assignment(@flexible, 30)
    create_assignment(@evaluated, 30)
    create_assignment(@learn, 30)

    # weighted_sum = 80*0.2 + 30*0.2 + 30*0.2 + 30*0.2 + 30*0.1 + 30*0.1 = 16+6+6+6+3+3 = 40
    # cap = 80, 40 < 80 -> no cap applied
    result = ClauseScoreCalculator.new(@tool_clause).calculate_score(@company)

    assert_equal false, result[:cap_applied]
    assert_in_delta 40.0, result[:percentage], 0.01
  end

  private

  def create_assignment(subcheckpoint, percentage_score, company = nil)
    company ||= @company
    ToolClauseSubcheckpointAssignment.create!(
      tool_clause: @tool_clause,
      tool_subcheckpoint: subcheckpoint,
      company: company,
      percentage_score: percentage_score,
      status: "approved"
    )
  end
end
