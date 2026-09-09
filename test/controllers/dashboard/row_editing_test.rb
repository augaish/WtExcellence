require "test_helper"

# R12 — rows could be deleted but not corrected.
class Dashboard::RowEditingTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!

    @company = Company.create!(name: "Rows Co #{SecureRandom.hex(4)}", license_seats: 10, credits: 50, is_active: true)
    @admin = User.create!(email: "rows-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: "Rows Admin", is_active: true)
    CompanyUser.create!(company: @company, user: @admin, role: CompanyUser::ROLES[:company_admin])
    sign_in @admin
  end

  test "a service level can be corrected in place" do
    sla = @company.pp_records.create!(record_type: "sla", title_en: "SLA")
    level = sla.service_levels.create!(service_name: "Portal", metric: "availability", target_value: 99, target_unit: "percent")

    patch dashboard_pp_record_service_level_path(sla, level), params: {
      pp_service_level: { target_value: 99.9, remedy: "Service credit" }
    }

    assert_redirected_to dashboard_pp_record_path(sla)
    assert_equal 99.9, level.reload.target_value.to_f
    assert_equal "Service credit", level.remedy
    assert_equal "Portal", level.service_name, "unrelated fields survive the edit"
  end

  test "a step can be corrected in place and the total follows" do
    procedure = @company.pp_records.create!(record_type: "procedure", title_en: "P", pp_process: level_two_process(@company), current_stage: "s2_prep")
    step = procedure.steps.create!(position: 1, activity: "Draft", duration_value: 2, duration_unit: "hours")

    patch dashboard_pp_record_record_step_path(procedure, step), params: { pp_process_step: { duration_value: 5 } }

    assert_equal 5, step.reload.duration_value
    assert_equal 300, procedure.reload.computed_total_minutes
  end

  test "the step and SLA pages offer an edit for each row" do
    procedure = @company.pp_records.create!(record_type: "procedure", title_en: "P", pp_process: level_two_process(@company), current_stage: "s2_prep")
    step = procedure.steps.create!(position: 1, activity: "Draft")
    get dashboard_documenter_record_path(procedure)
    assert_select "form[action=?]", dashboard_pp_record_record_step_path(procedure, step)

    sla = @company.pp_records.create!(record_type: "sla", title_en: "SLA")
    level = sla.service_levels.create!(service_name: "Portal", metric: "availability")
    get dashboard_pp_record_path(sla)
    assert_select "form[action=?]", dashboard_pp_record_service_level_path(sla, level)
  end

  test "the diagram can be drawn from the steps through the page" do
    process = @company.pp_processes.create!(name_en: "P", level: 2, category: "core", parent: @company.pp_processes.create!(name_en: "L1 " + "P", level: 1, category: "core"))
    process.steps.create!(position: 1, activity: "Draft", responsible_title: "Officer")
    diagram = @company.pp_diagrams.create!(owner: process, name: "Flow")

    post generate_from_steps_dashboard_pp_diagram_path(diagram)

    assert_redirected_to dashboard_pp_diagram_path(diagram)
    assert_equal 3, diagram.reload.elements.count
    follow_redirect!
    assert_includes response.body, I18n.t("architect.sync.linked", position: 1)
  end
end
