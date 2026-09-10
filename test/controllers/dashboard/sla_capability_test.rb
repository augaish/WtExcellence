require "test_helper"

# Section 7 of Review 03: an agreement names its other party, its levels say
# how they are compared and measured, and attainment comes from reviewed
# measurements rather than from the promise.
class Dashboard::SlaCapabilityTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!
    @company = Company.create!(name: "SLA #{SecureRandom.hex(4)}", license_seats: 10, credits: 50, is_active: true)
    @admin = user("sla-admin", CompanyUser::ROLES[:company_admin])
    @qm = user("sla-qm", CompanyUser::ROLES[:company_quality_manager])
    @it = @company.org_units.create!(name_en: "IT", level: 1, code: "IT")
    @finance = @company.org_units.create!(name_en: "Finance", level: 1, code: "FIN")
    sign_in @admin
  end

  test "Agreements is a tab, and an agreement must name its other party, typed" do
    get dashboard_pp_records_path
    assert_select "a[href=?]", dashboard_pp_records_path(record_type: "sla")

    post dashboard_pp_records_path, params: { pp_record: { record_type: "sla", title_en: "Portal hosting", owner_org_unit_id: @it.id } }
    assert_response :unprocessable_entity, "no other party named"

    post dashboard_pp_records_path, params: { pp_record: { record_type: "sla", title_en: "Portal hosting", owner_org_unit_id: @it.id,
      counterparty_kind: "internal_unit", counterparty_org_unit_id: @finance.id } }
    sla = @company.pp_records.find_by(title_en: "Portal hosting")
    assert_equal "SLA-IT-001-V1", sla.code
    assert_equal "Finance", sla.counterparty_label(:en)

    post dashboard_pp_records_path, params: { pp_record: { record_type: "sla", title_en: "Bank A hosting", owner_org_unit_id: @it.id,
      counterparty_kind: "customer", counterparty: "Bank A" } }
    assert_equal "Bank A (a customer)", @company.pp_records.find_by(title_en: "Bank A hosting").counterparty_label(:en)
  end

  test "a level carries comparator, period and source; units must suit; not measurable without target and method" do
    sla = @company.pp_records.create!(record_type: "sla", title_en: "Hosting", owner_org_unit: @it, counterparty_kind: "customer", counterparty: "Bank A")

    post dashboard_pp_record_service_levels_path(sla), params: { pp_service_level: { service_name: "Availability", metric: "availability", target_value: 101, target_unit: "percent", measurement_method: "Monitoring" } }
    assert_equal 0, sla.service_levels.count, "101% is refused"
    post dashboard_pp_record_service_levels_path(sla), params: { pp_service_level: { service_name: "Availability", metric: "availability", target_value: 99.9, target_unit: "hours", measurement_method: "Monitoring" } }
    assert_equal 0, sla.service_levels.count, "availability in hours is refused"

    post dashboard_pp_record_service_levels_path(sla), params: { pp_service_level: { service_name: "Availability", metric: "availability", target_value: 99.9, target_unit: "percent",
      measurement_method: "Monitoring tool, monthly", measurement_period: "monthly", measurement_source: "Uptime dashboard", exclusions: "Planned maintenance" } }
    level = sla.service_levels.sole
    assert_equal "at_least", level.comparator, "availability compares upward by default"
    assert level.measurable?

    post dashboard_pp_record_service_levels_path(sla), params: { pp_service_level: { service_name: "Advisory", metric: "other", measurement_method: "" } }
    advisory = sla.service_levels.find_by(service_name: "Advisory")
    refute advisory.measurable?
    section = RecordDocument.new(sla.reload).sections.find { |s| s.key == "service_levels" }
    assert_includes section.payload.map { |r| r[:status] }, I18n.t("sla.status.target_missing")
  end

  test "attainment is counted from reviewed measurements, judged by the comparator, with four eyes" do
    sla = @company.pp_records.create!(record_type: "sla", title_en: "Hosting", owner_org_unit: @it, counterparty_kind: "customer", counterparty: "Bank A")
    availability = sla.service_levels.create!(service_name: "Availability", metric: "availability", target_value: 99.9, target_unit: "percent", measurement_method: "Monitoring")
    response_time = sla.service_levels.create!(service_name: "Response", metric: "response_time", target_value: 4, target_unit: "hours", measurement_method: "Ticket system")
    assert_nil availability.attainment_percent, "nothing measured, no attainment"

    post dashboard_pp_record_service_level_measurements_path(sla, availability), params: { sla_measurement: { period_start: "2026-08-01", period_end: "2026-08-31", actual_value: 99.95 } }
    post dashboard_pp_record_service_level_measurements_path(sla, availability), params: { sla_measurement: { period_start: "2026-07-01", period_end: "2026-07-31", actual_value: 99.5 } }
    post dashboard_pp_record_service_level_measurements_path(sla, response_time), params: { sla_measurement: { period_start: "2026-08-01", period_end: "2026-08-31", actual_value: 5 } }
    assert_equal [ false, true ], availability.measurements.reorder(:period_start).map(&:met?), "July 99.5 breached, August 99.95 met"
    refute response_time.measurements.sole.met?, "5 hours against at most 4 is a breach"
    assert_nil availability.reload.attainment_percent, "unreviewed measurements do not count"

    august = availability.measurements.find_by(period_start: Date.new(2026, 8, 1))
    patch review_dashboard_pp_record_service_level_measurement_path(sla, availability, august)
    refute august.reload.reviewed?, "the recorder cannot review their own number"

    sign_out @admin
    sign_in @qm
    availability.measurements.each { |m| patch review_dashboard_pp_record_service_level_measurement_path(sla, availability, m) }
    assert_equal 50.0, availability.reload.attainment_percent
    assert_equal 1, availability.breaches

    get dashboard_pp_record_path(sla)
    assert_select "body", text: /50\.0%/
    section = RecordDocument.new(sla.reload).sections.find { |s| s.key == "service_levels" }
    assert_equal "50.0%", section.payload.first[:attainment]
  end

  test "a measurement cannot be recorded against a level nobody can measure" do
    sla = @company.pp_records.create!(record_type: "sla", title_en: "Hosting", owner_org_unit: @it, counterparty_kind: "customer", counterparty: "Bank A")
    advisory = sla.service_levels.create!(service_name: "Advisory", metric: "other")
    post dashboard_pp_record_service_level_measurements_path(sla, advisory), params: { sla_measurement: { period_start: "2026-08-01", period_end: "2026-08-31", actual_value: 1 } }
    assert_equal 0, advisory.measurements.count
  end

  private

  def user(tag, role)
    u = User.create!(email: "#{tag}-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: tag, is_active: true)
    CompanyUser.create!(company: @company, user: u, role: role)
    u
  end
end
