require "test_helper"

class PpServiceLevelTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "SLA Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @sla = @company.pp_records.create!(record_type: "sla", title_en: "Support Services SLA",
      counterparty: "Ministry of Tourism")
  end

  test "an agreement records the party it is with" do
    assert_equal "Ministry of Tourism", @sla.counterparty
    assert_predicate @sla, :sla?
  end

  test "a target reads the way someone would say it" do
    availability = @sla.service_levels.create!(service_name: "Portal", metric: "availability",
      target_value: 99.9, target_unit: "percent")
    response = @sla.service_levels.create!(service_name: "Support", metric: "response_time",
      target_value: 4, target_unit: "hours")

    assert_equal "99.9 %", availability.target_label
    assert_equal "4 hours", response.target_label, "a whole number should not read as 4.0"
  end

  test "a unit that does not suit the commitment is refused" do
    level = @sla.service_levels.new(metric: "availability", target_value: 4, target_unit: "hours")

    assert_not level.valid?
    assert_predicate level.errors[:target_unit], :present?
  end

  test "a percentage cannot exceed one hundred" do
    level = @sla.service_levels.new(metric: "availability", target_value: 150, target_unit: "percent")

    assert_not level.valid?
    assert_predicate level.errors[:target_value], :present?
  end

  test "a commitment with no target or method is not measurable" do
    intent = @sla.service_levels.create!(service_name: "Best effort", metric: "other")
    measurable = @sla.service_levels.create!(service_name: "Portal", metric: "availability",
      target_value: 99.5, target_unit: "percent", measurement_method: "Monthly uptime report")

    assert_not intent.measurable?
    assert measurable.measurable?
  end

  test "the generated document prints the service levels of an agreement" do
    @sla.service_levels.create!(service_name: "Portal", metric: "availability",
      target_value: 99.9, target_unit: "percent", measurement_method: "Monthly uptime report")

    section = RecordDocument.new(@sla.reload).sections.find { |s| s.key == "service_levels" }
    assert section, "an SLA should print its service levels"
    assert_equal "Portal", section.payload.first[:service]
    assert_equal "at least 99.9 %", section.payload.first[:target], "the comparator prints with the target"
  end

  test "a policy prints no service levels section" do
    policy = @company.pp_records.create!(record_type: "policy", title_en: "A policy", description: "Text.")

    keys = RecordDocument.new(policy).sections.map(&:key)
    assert_not_includes keys, "service_levels"
  end
end
