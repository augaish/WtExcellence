require "test_helper"

class Dashboard::PpProcessesControllerTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!

    @company = Company.create!(name: "ProcCtl #{SecureRandom.hex(4)}", license_seats: 10, credits: 50, is_active: true)

    @admin = User.create!(email: "proc-admin-#{SecureRandom.hex(4)}@example.com",
      password: "password123", password_confirmation: "password123", name: "Admin", is_active: true)
    CompanyUser.create!(company: @company, user: @admin, role: CompanyUser::ROLES[:company_admin])

    @viewer = User.create!(email: "proc-viewer-#{SecureRandom.hex(4)}@example.com",
      password: "password123", password_confirmation: "password123", name: "Viewer", is_active: true)
    CompanyUser.create!(company: @company, user: @viewer, role: CompanyUser::ROLES[:company_viewer])

    @l1 = @company.pp_processes.create!(name_en: "Governance", level: 1, code: "P-01", category: "management")
  end

  test "index renders the process tree" do
    sign_in @admin
    get dashboard_pp_processes_path

    assert_response :success
    assert_select "body", text: /Governance/
  end

  test "a viewer sees the tree without manage actions" do
    sign_in @viewer
    get dashboard_pp_processes_path

    assert_response :success
    assert_select "a[href=?]", new_dashboard_pp_process_path, count: 0
  end

  test "admin creates a level 2 process under a parent" do
    sign_in @admin

    assert_difference -> { @company.pp_processes.count }, 1 do
      post dashboard_pp_processes_path, params: {
        pp_process: { name_en: "Policy Management", name_ar: "إدارة السياسات", level: 2,
                      parent_id: @l1.id, objective: "Manage policies", trigger_text: "New request",
                      inputs: "Draft", outputs: "Published policy", frequency: "on_demand" }
      }
    end

    process = @company.pp_processes.find_by(name_en: "Policy Management")
    assert_equal 2, process.level
    assert_equal @l1.id, process.parent_id
    assert_equal "management", process.effective_category
    assert_equal "New request", process.trigger_text
  end

  test "rejects a level that skips a tier" do
    sign_in @admin

    post dashboard_pp_processes_path, params: {
      pp_process: { name_en: "Too deep", level: 3, parent_id: @l1.id }
    }

    assert_response :unprocessable_entity
    assert_nil @company.pp_processes.find_by(name_en: "Too deep")
  end

  test "new form suggests a nested process code" do
    sign_in @admin
    get new_dashboard_pp_process_path(parent_id: @l1.id)

    assert_response :success
    assert_select "input[name='pp_process[code]'][value=?]", "P-01-01"
  end

  test "the process card exposes every spec field" do
    sign_in @admin
    get new_dashboard_pp_process_path

    assert_response :success
    %w[objective trigger_text inputs outputs predecessor_process_id successor_process_id
       frequency total_time_value total_time_unit automation_status related_policies
       technical_systems forms_used kpis].each do |field|
      assert_select "[name='pp_process[#{field}]']", { minimum: 1 }, "missing field #{field}"
    end
  end

  test "category filter narrows the tree" do
    sign_in @admin
    @company.pp_processes.create!(name_en: "Core Ops", level: 1, code: "P-02", category: "core")

    get dashboard_pp_processes_path(category: "core")

    assert_response :success
    assert_select "body", text: /Core Ops/
  end

  test "a process with children cannot be deleted" do
    sign_in @admin
    @company.pp_processes.create!(name_en: "Child", level: 2, parent: @l1)

    assert_no_difference -> { @company.pp_processes.count } do
      delete dashboard_pp_process_path(@l1)
    end
  end

  test "the CSV template downloads with the documented headers" do
    sign_in @admin
    get template_dashboard_pp_processes_path

    assert_response :success
    assert_includes response.body, "code,name_en,name_ar,level,parent_code,category"
  end
end
