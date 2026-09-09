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

  test "the plus on a level opens the form at that level" do
    sign_in @admin
    get new_dashboard_pp_process_path(level: 2)
    assert_response :success
    assert_select "select[name='pp_process[level]'] option[selected][value='2']"

    get new_dashboard_pp_process_path(parent_id: @l1.id)
    assert_response :success
    assert_select "select[name='pp_process[parent_id]'] option[selected][value=?]", @l1.id.to_s
  end

  test "the index shows Level 0, 1 and 2 boxes with a plus and no Add process button" do
    sign_in @admin
    get dashboard_pp_processes_path

    assert_select "a[href=?]", new_dashboard_pp_process_path(level: 1)
    assert_select "a[href=?]", new_dashboard_pp_process_path(level: 2)
    assert_select "a[href=?]", new_dashboard_pp_process_path, count: 0
    assert_select "body", text: /Level 0/
  end

  test "the model view draws the bands with level 1 boxes, level 2 inside, and the objective" do
    sign_in @admin
    child = @company.pp_processes.create!(name_en: "Policy drafting", level: 2, parent: @l1)
    @company.update!(process_objective_en: "Develop the largest urban park")

    get dashboard_pp_processes_path(view: "model")

    assert_response :success
    assert_select "section[aria-labelledby='band-management']", text: /Governance/
    assert_select "section[aria-labelledby='band-management']", text: /Policy drafting/
    assert_select "section[aria-labelledby='band-management']", text: /#{Regexp.escape(child.architecture_number)}/
    assert_select "body", text: /Develop the largest urban park/
  end

  test "an admin renames the bands and sets the objective" do
    sign_in @admin

    patch settings_dashboard_pp_processes_path, params: {
      band_names: { management: { en: "Managerial processes", ar: "العمليات الإدارية" } },
      process_objective_en: "One of the world's largest parks", process_objective_ar: "أكبر الحدائق"
    }

    assert_redirected_to dashboard_pp_processes_path(view: "model")
    @company.reload
    assert_equal "Managerial processes", @company.process_band_name("management", :en)
    assert_equal "العمليات الإدارية", @company.process_band_name("management", :ar)
    assert_equal "Core", @company.process_band_name("core", :en)
    assert_equal "One of the world's largest parks", @company.process_objective(:en)

    get dashboard_pp_processes_path(view: "model")
    assert_select "body", text: /Managerial processes/
  end

  test "a viewer cannot change the architecture settings" do
    sign_in @viewer
    patch settings_dashboard_pp_processes_path, params: { process_objective_en: "Nope" }
    assert_redirected_to dashboard_pp_processes_path
    assert_nil @company.reload.process_objective_en
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
