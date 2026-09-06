require "test_helper"

# The routing rules are the heart of the Documenter: given where a record is and
# what it is, exactly one stage comes next.
class PpStageTest < ActiveSupport::TestCase
  test "the sequence has every stage the product owner specified" do
    assert_equal 17, PpStage::KEYS.size
    %w[s1_verify s1_approved s2_prep s2_draftReview s2_ownerReview s2_comments
       s2_confirmation s2_stakeholders s2_final s3_design s3_designReview
       s4_initial s4_ownerapprove s4_final s5_toPublish s5_published s5_closed].each do |key|
      assert PpStage.exists?(key), "missing stage #{key}"
    end
  end

  test "the deleted stakeholder-approval stage is gone" do
    refute PpStage.exists?("s4_stakeholders")
  end

  test "the two new stages are present" do
    assert PpStage.exists?("s2_confirmation")
    assert PpStage.exists?("s4_ownerapprove")
  end

  test "plain stages advance one step" do
    assert_equal "s1_approved", PpStage.next_key("s1_verify", record_type: "policy")
    assert_equal "s2_prep", PpStage.next_key("s1_approved", record_type: "policy")
    assert_equal "s2_draftReview", PpStage.next_key("s2_prep", record_type: "policy")
  end

  # Branch 1: the intersections answer decides whether stakeholders review it.
  test "confirmation routes to stakeholder review only when there are intersections" do
    assert_equal "s2_stakeholders",
      PpStage.next_key("s2_confirmation", record_type: "policy", has_intersections: true)
    assert_equal "s2_final",
      PpStage.next_key("s2_confirmation", record_type: "policy", has_intersections: false)
  end

  # Branch 2: only Procedures go through the design phase.
  test "the final draft routes procedures to design and everything else to approval" do
    assert_equal "s3_design", PpStage.next_key("s2_final", record_type: "procedure")
    assert_equal "s4_initial", PpStage.next_key("s2_final", record_type: "policy")
    assert_equal "s4_initial", PpStage.next_key("s2_final", record_type: "form")
  end

  test "design review rejoins the approval phase" do
    assert_equal "s3_designReview", PpStage.next_key("s3_design", record_type: "procedure")
    assert_equal "s4_initial", PpStage.next_key("s3_designReview", record_type: "procedure")
  end

  test "the approval phase runs initial then owner then final" do
    assert_equal "s4_ownerapprove", PpStage.next_key("s4_initial", record_type: "policy")
    assert_equal "s4_final", PpStage.next_key("s4_ownerapprove", record_type: "policy")
    assert_equal "s5_toPublish", PpStage.next_key("s4_final", record_type: "policy")
  end

  test "publishing ends at closed, which is terminal" do
    assert_equal "s5_published", PpStage.next_key("s5_toPublish", record_type: "policy")
    assert_equal "s5_closed", PpStage.next_key("s5_published", record_type: "policy")
    assert_nil PpStage.next_key("s5_closed", record_type: "policy")
    assert PpStage.terminal?("s5_closed")
  end

  # Walking forward must never drop a record into a stage it skips.
  test "a policy without intersections never lands on a skipped stage" do
    route = PpStage.route_for(record_type: "policy", has_intersections: false)

    refute_includes route, "s2_stakeholders"
    refute_includes route, "s3_design"
    refute_includes route, "s3_designReview"
    assert_includes route, "s2_final"
    assert_includes route, "s4_ownerapprove"
  end

  test "a procedure with intersections takes the longest route" do
    route = PpStage.route_for(record_type: "procedure", has_intersections: true)

    assert_includes route, "s2_stakeholders"
    assert_includes route, "s3_design"
    assert_equal PpStage::KEYS.size, route.size
  end

  test "walking the whole route reaches the terminal stage for every type" do
    PpRecord::TYPES.each do |type|
      [ true, false ].each do |intersections|
        stage = PpStage::FIRST_KEY
        steps = 0
        while (nxt = PpStage.next_key(stage, record_type: type, has_intersections: intersections))
          stage = nxt
          steps += 1
          flunk "route for #{type} did not terminate" if steps > 30
        end
        assert_equal PpStage::TERMINAL_KEY, stage, "#{type} (intersections=#{intersections}) ended at #{stage}"
      end
    end
  end

  test "forward? accepts only the single computed next stage" do
    assert PpStage.forward?("s2_confirmation", "s2_final", record_type: "policy", has_intersections: false)
    refute PpStage.forward?("s2_confirmation", "s2_stakeholders", record_type: "policy", has_intersections: false)
    # No jumping ahead.
    refute PpStage.forward?("s1_verify", "s5_published", record_type: "policy")
  end

  test "backward? accepts earlier stages on the route and nothing else" do
    assert PpStage.backward?("s2_final", "s2_prep", record_type: "policy")
    refute PpStage.backward?("s2_prep", "s2_final", record_type: "policy")
    # A stage that is not on a policy's route is not a legal return target.
    refute PpStage.backward?("s4_initial", "s3_design", record_type: "policy")
    assert PpStage.backward?("s4_initial", "s3_design", record_type: "procedure")
  end

  test "approval and branch stages are identified" do
    assert PpStage.approval_stage?("s2_stakeholders")
    assert PpStage.approval_stage?("s4_final")
    refute PpStage.approval_stage?("s2_prep")
    assert PpStage.branch_stage?("s2_confirmation")
  end

  test "every stage belongs to a known phase" do
    PpStage::KEYS.each do |key|
      assert_includes PpStage::PHASES, PpStage.phase_of(key), "#{key} has no valid phase"
    end
  end
end
