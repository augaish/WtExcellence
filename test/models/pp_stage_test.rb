require "test_helper"

# The lifecycle as the product owner described it, one route per kind of
# record, with exactly one legal next step from anywhere.
class PpStageTest < ActiveSupport::TestCase
  test "policies, forms and services take the document route" do
    expected = %w[s1_verify s1_approved s2_prep s2_draftReview s2_stakeholders s4_final s5_toPublish s5_published]
    %w[policy form service].each do |type|
      assert_equal expected, PpStage.route_for(record_type: type), type
    end
  end

  test "procedures add design and design review after stakeholder review" do
    route = PpStage.route_for(record_type: "procedure")
    assert_equal %w[s2_stakeholders s3_design s3_designReview s4_final], route[4, 4]
  end

  test "a glossary term is one approval away from being visible" do
    assert_equal %w[g1_submitted g2_published], PpStage.route_for(record_type: "glossary")
    assert_equal "g1_submitted", PpStage.first_key_for("glossary")
    assert PpStage.terminal?("g2_published")
  end

  test "next_key walks each route to its end and nowhere else" do
    %w[policy procedure glossary].each do |type|
      route = PpStage.route_for(record_type: type)
      route.each_cons(2) { |from, to| assert_equal to, PpStage.next_key(from, record_type: type) }
      assert_nil PpStage.next_key(route.last, record_type: type)
    end
    assert_nil PpStage.next_key("s3_design", record_type: "policy"), "a policy never sits in design"
  end

  test "every stage names who acts in it" do
    assert_equal :verifier, PpStage.actor_of("s1_verify")
    assert_equal :pp_manager, PpStage.actor_of("s1_approved")
    assert_equal :unit_head, PpStage.actor_of("s2_prep")
    assert_equal :approvers, PpStage.actor_of("s2_stakeholders")
    assert_equal :publisher, PpStage.actor_of("s5_toPublish")
    assert_nil PpStage.actor_of("s5_published")
  end

  test "approval and publish stages are identified" do
    assert PpStage.approval_stage?("s2_stakeholders")
    assert PpStage.approval_stage?("s4_final")
    assert PpStage.publish_stage?("s5_toPublish")
    refute PpStage.approval_stage?("s2_prep")
  end

  test "forward? accepts only the single computed next stage" do
    assert PpStage.forward?("s2_stakeholders", "s3_design", record_type: "procedure")
    refute PpStage.forward?("s2_stakeholders", "s3_design", record_type: "policy")
    assert PpStage.forward?("s2_stakeholders", "s4_final", record_type: "policy")
  end

  test "backward? accepts earlier stages on the route and nothing else" do
    assert PpStage.backward?("s4_final", "s2_prep", record_type: "policy")
    refute PpStage.backward?("s2_prep", "s4_final", record_type: "policy")
    refute PpStage.backward?("s4_final", "s3_design", record_type: "policy"), "not on a policy's route"
    assert PpStage.backward?("s4_final", "s3_design", record_type: "procedure")
  end

  test "every stage has a label in both languages" do
    PpStage::KEYS.each do |key|
      assert_not_equal key, PpStage.label(key, :en)
      assert_not_equal key, PpStage.label(key, :ar)
    end
  end
end
