require "test_helper"

class PpMonitoringServiceTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Mon Co #{SecureRandom.hex(4)}", license_seats: 10, is_active: true)
    @user = User.create!(email: "mon-#{SecureRandom.hex(4)}@example.com",
      password: "password123", password_confirmation: "password123", name: "Admin", is_active: true)
    CompanyUser.create!(company: @company, user: @user, role: CompanyUser::ROLES[:company_admin])
    @service = PpMonitoringService.for(@company)
  end

  def record(stage: PpStage::FIRST_KEY, entered: Time.current, unit: nil, **attrs)
    @company.pp_records.create!(
      { record_type: "policy", title_en: "Doc #{SecureRandom.hex(3)}",
        current_stage: stage, stage_entered_at: entered, owner_org_unit: unit }.merge(attrs)
    )
  end

  # --- Calculation 1: funnel ---------------------------------------------

  test "the funnel has one bar per lifecycle phase" do
    funnel = @service.funnel

    assert_equal PpStage::PHASES.size, funnel.size
    assert_equal PpStage::PHASES, funnel.map { |f| f[:phase] }
  end

  # "reached" counts everything at or PAST the phase, not just sitting in it.
  test "reached counts records at or past each phase" do
    record(stage: "s1_verify")
    record(stage: "s4_final")

    funnel = PpMonitoringService.for(@company.reload).funnel
    by_phase = funnel.index_by { |f| f[:phase] }

    assert_equal 2, by_phase["inventory"][:reached], "both records have reached inventory"
    assert_equal 1, by_phase["approval"][:reached], "only one has reached approval"
    assert_equal 0, by_phase["publishing"][:reached]
  end

  test "percentages use the configured yearly target when set" do
    4.times { record }
    @company.update!(pp_yearly_target: 8)

    funnel = PpMonitoringService.for(@company.reload).funnel
    inventory = funnel.detect { |f| f[:phase] == "inventory" }

    assert_equal 8, inventory[:total]
    assert_in_delta 50.0, inventory[:pct], 0.1
  end

  test "percentages fall back to the record count with no target" do
    4.times { record }

    funnel = PpMonitoringService.for(@company.reload).funnel
    inventory = funnel.detect { |f| f[:phase] == "inventory" }

    assert_equal 4, inventory[:total]
    assert_in_delta 100.0, inventory[:pct], 0.1
  end

  test "an empty company does not divide by zero" do
    funnel = @service.funnel
    assert funnel.all? { |f| f[:pct] == 0.0 }
  end

  # --- Calculation 2: work status ----------------------------------------

  test "a record at the first stage that has never moved is notStarted" do
    r = record(stage: PpStage::FIRST_KEY)
    assert_equal "not_started", PpMonitoringService.for(@company.reload).status_for(r)
  end

  test "a record that has moved is no longer notStarted" do
    r = record(stage: "s2_prep")
    r.stage_transitions.create!(from_stage: "s1_verify", to_stage: "s2_prep", direction: "forward")

    assert_equal "on_track", PpMonitoringService.for(@company.reload).status_for(r.reload)
  end

  # Precedence: late beats onTrack.
  test "a record sitting past its stage target is late" do
    @company.pp_stage_targets.create!(stage_key: "s2_prep", target_days: 1)
    r = record(stage: "s2_prep", entered: 40.days.ago)
    r.stage_transitions.create!(from_stage: "s1_verify", to_stage: "s2_prep", direction: "forward")

    assert_equal "late", PpMonitoringService.for(@company.reload).status_for(r.reload)
  end

  test "a finished record whose history is clean is completed" do
    r = record(stage: "s5_published", entered: Time.current)
    r.stage_transitions.create!(from_stage: "s5_toPublish", to_stage: "s5_published", direction: "forward")

    assert_equal "completed", PpMonitoringService.for(@company.reload).status_for(r.reload)
  end

  # The optional fourth state, available because the transition history exists.
  test "a finished record with an overrunning past stage is completedLate" do
    @company.pp_stage_targets.create!(stage_key: "s1_verify", target_days: 1)
    r = record(stage: "s5_published")
    r.update_column(:created_at, 60.days.ago)
    # It sat in s1_verify for ~40 days against a 1-day target.
    r.stage_transitions.create!(from_stage: "s1_verify", to_stage: "s1_approved", direction: "forward")
    r.stage_transitions.last.update_column(:created_at, 20.days.ago)

    assert_equal "completed_late", PpMonitoringService.for(@company.reload).status_for(r.reload)
  end

  test "the breakdown counts every record exactly once" do
    3.times { record }
    r = record(stage: "s5_published")
    r.stage_transitions.create!(from_stage: "s5_toPublish", to_stage: "s5_published", direction: "forward")

    breakdown = PpMonitoringService.for(@company.reload).status_breakdown

    assert_equal 4, breakdown.values.sum
    assert_equal 3, breakdown["not_started"]
  end

  # --- Calculation 3: roll-up --------------------------------------------

  test "a leaf unit reports its own completion" do
    unit = @company.org_units.create!(name_en: "Finance", level: 1)
    record(unit: unit, stage: "s5_published")
    record(unit: unit, stage: "s2_prep")

    node = PpMonitoringService.for(@company.reload).rollup.first

    assert_equal "Finance", node[:name]
    assert_in_delta 50.0, node[:completion_pct], 0.1
  end

  # The rule that matters: children count EQUALLY, not by record volume.
  test "a parent averages its children with equal weight, not by record count" do
    parent = @company.org_units.create!(name_en: "Group", level: 1)
    big = @company.org_units.create!(name_en: "Big", level: 2, parent: parent)
    small = @company.org_units.create!(name_en: "Small", level: 2, parent: parent)

    # Big: 40 records, none complete (0%). Small: 2 records, both complete (100%).
    40.times { record(unit: big, stage: "s2_prep") }
    2.times { record(unit: small, stage: "s5_published") }

    node = PpMonitoringService.for(@company.reload).rollup.first

    # Equal weight => (0 + 100) / 2 = 50, NOT weighted by 40 vs 2 (which would be ~4.8).
    assert_in_delta 50.0, node[:completion_pct], 0.1
    assert_equal 42, node[:total_records]
  end

  test "a node with no records of its own takes its numbers from its children" do
    parent = @company.org_units.create!(name_en: "Group", level: 1)
    child = @company.org_units.create!(name_en: "Child", level: 2, parent: parent)
    record(unit: child, stage: "s5_published")

    node = PpMonitoringService.for(@company.reload).rollup.first

    assert_equal 0, node[:own_records]
    assert_in_delta 100.0, node[:completion_pct], 0.1
  end

  test "a node is notStarted only when every descendant is" do
    parent = @company.org_units.create!(name_en: "Group", level: 1)
    a = @company.org_units.create!(name_en: "A", level: 2, parent: parent)
    b = @company.org_units.create!(name_en: "B", level: 2, parent: parent)
    record(unit: a)
    record(unit: b)

    node = PpMonitoringService.for(@company.reload).rollup.first
    assert node[:not_started], "nothing has moved yet"

    # One deep descendant starting is enough to mark the whole branch started.
    moved = @company.pp_records.where(owner_org_unit_id: b.id).first
    moved.update!(current_stage: "s2_prep")
    moved.stage_transitions.create!(from_stage: "s1_verify", to_stage: "s2_prep", direction: "forward")

    node = PpMonitoringService.for(@company.reload).rollup.first
    assert node[:started]
    refute node[:not_started]
  end

  test "the roll-up nests to the depth of the org tree" do
    l1 = @company.org_units.create!(name_en: "L1", level: 1)
    l2 = @company.org_units.create!(name_en: "L2", level: 2, parent: l1)
    @company.org_units.create!(name_en: "L3", level: 3, parent: l2)

    node = PpMonitoringService.for(@company.reload).rollup.first

    assert_equal "L1", node[:name]
    assert_equal "L2", node[:children].first[:name]
    assert_equal "L3", node[:children].first[:children].first[:name]
  end
end
