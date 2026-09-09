require "test_helper"

class PpProcessStepTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Steps Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @process = @company.pp_processes.create!(name_en: "Policy development", level: 1, category: "core")
    @unit = @company.org_units.create!(name_en: "Institutional Excellence", level: 1)
  end

  test "a duration needs a unit" do
    step = @process.steps.new(position: 1, activity: "Draft", duration_value: 3)

    assert_not step.valid?
    assert_predicate step.errors[:duration_unit], :present?
  end

  test "durations convert to minutes so mixed units can be summed" do
    minutes = @process.steps.create!(position: 1, duration_value: 30, duration_unit: "minutes")
    hours = @process.steps.create!(position: 2, duration_value: 2, duration_unit: "hours")
    days = @process.steps.create!(position: 3, duration_value: 1, duration_unit: "days")

    assert_equal 30, minutes.duration_in_minutes
    assert_equal 120, hours.duration_in_minutes
    assert_equal 480, days.duration_in_minutes
  end

  test "the process total is summed from its steps, not typed" do
    @process.steps.create!(position: 1, duration_value: 4, duration_unit: "hours")
    @process.steps.create!(position: 2, duration_value: 1, duration_unit: "days")

    assert_equal 720, @process.reload.computed_total_minutes
    assert_equal 12, @process.computed_total_in("hours")
    assert_equal 1.5, @process.computed_total_in("days")
  end

  test "a process with no step durations has no computed total" do
    @process.steps.create!(position: 1, activity: "Draft")

    assert_nil @process.reload.computed_total_minutes
  end

  test "a typed total that the steps contradict is flagged" do
    @process.steps.create!(position: 1, duration_value: 4, duration_unit: "hours")
    @process.update!(total_time_value: 9, total_time_unit: "hours")

    assert @process.reload.total_time_disagrees_with_steps?

    @process.update!(total_time_value: 4)
    assert_not @process.reload.total_time_disagrees_with_steps?
  end

  test "the responsible party is a position, with the unit as a fallback" do
    titled = @process.steps.create!(position: 1, responsible_title: "Policies Director")
    unit_only = @process.steps.create!(position: 2, responsible_org_unit: @unit)

    assert_equal "Policies Director", titled.responsible_label
    assert_equal "Institutional Excellence", unit_only.responsible_label
  end

  test "a step cannot name another company's unit" do
    other = Company.create!(name: "Other #{SecureRandom.hex(4)}", license_seats: 5, credits: 1, is_active: true)
    foreign_unit = other.org_units.create!(name_en: "Foreign", level: 1)
    step = @process.steps.new(position: 1, responsible_org_unit: foreign_unit)

    assert_not step.valid?
    assert_predicate step.errors[:responsible_org_unit], :present?
  end
end
