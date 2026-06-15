require "test_helper"
require "minitest/mock"
require "csv"
require "zip"

class Dashboard::CapaManagementControllerTest < ActionDispatch::IntegrationTest
  setup do
    CreditService.clear_cache
    AiActionCredit.ensure_defaults!

    @company = Company.create!(
      name: "Test Company",
      license_seats: 5,
      credits: 100,
      is_active: true,
      default_locale: "en"
    )

    @user = User.create!(
      email: "controller_tester@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "Controller Tester",
      is_active: true
    )

    @company_user = CompanyUser.create!(
      company: @company,
      user: @user,
      role: CompanyUser::ROLES[:company_admin],
      assigned_credits: 0
    )

    @assignee_user = User.create!(
      email: "assigned_user@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "Assigned User"
    )

    @assignee_company_user = CompanyUser.create!(
      company: @company,
      user: @assignee_user,
      role: CompanyUser::ROLES[:company_admin],
      assigned_credits: 0
    )

    @second_user = User.create!(
      email: "second_assigned@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "Second Assigned"
    )

    @second_company_user = CompanyUser.create!(
      company: @company,
      user: @second_user,
      role: CompanyUser::ROLES[:company_admin],
      assigned_credits: 0
    )

    @capa = Capa.create!(
      company: @company,
      title: "Root Cause CAPA",
      description: "Investigate root cause",
      source: "audit"
    )

    CapaAssignment.create!(capa: @capa, company_user: @assignee_company_user)
    @capa.update!(status: 'assigned')

    @questionnaire = Questionnaire.create!(
      capa: @capa,
      question_1: "Q1",
      question_2: "Q2",
      question_3: "Q3",
      question_4: "Q4",
      question_5: "Q5",
      answer_1: "A1",
      answer_2: "A2",
      answer_3: "A3",
      answer_4: "A4",
      answer_5: "A5",
      root_cause: "Old root cause"
    )

    sign_in @user, scope: :user
  end

  test "export applies archived and status filters" do
    archived_capa = Capa.create!(
      company: @company,
      title: "Archived Closed",
      description: "Closed and archived CAPA",
      source: "audit",
      status: "closed",
      priority: "low",
      archived: true,
      due_date: Date.today - 2
    )

    CapaAssignment.create!(capa: archived_capa, company_user: @second_company_user)

    archived_action = CapaAction.create!(
      capa: archived_capa,
      title: "Archived Action",
      action_type: "Corrective",
      status: "Done",
      due_date: Date.today - 1
    )
    CapaActionAssignment.create!(capa_action: archived_action, company_user: @second_company_user)

    open_capa = Capa.create!(
      company: @company,
      title: "Open Active",
      description: "Active CAPA",
      source: "audit",
      status: "open",
      priority: "high",
      due_date: Date.today + 5
    )

    CapaAssignment.create!(capa: open_capa, company_user: @assignee_company_user)
    active_action = CapaAction.create!(
      capa: open_capa,
      title: "Active Action",
      action_type: "Preventive",
      status: "Started",
      due_date: Date.today + 3
    )
    CapaActionAssignment.create!(capa_action: active_action, company_user: @assignee_company_user)

    get dashboard_export_capas_path, params: { status: "closed", archived_state: "archived" }

    assert_response :success
    assert_equal ["Archived Closed"], exported_titles
    assert_includes exported_action_titles, "Archived Action"
    refute_includes exported_action_titles, "Active Action"

    get dashboard_export_capas_path, params: { archived_state: "active", status: "all" }
    assert_response :success
    assert_includes exported_titles, "Open Active"
    refute_includes exported_titles, "Archived Closed"
    assert_includes exported_action_titles, "Active Action"
    refute_includes exported_action_titles, "Archived Action"
  end

  test "export filters by due date range priority and assignees" do
    matching_capa = Capa.create!(
      company: @company,
      title: "Target CAPA",
      description: "Should be exported",
      source: "audit",
      status: "assigned",
      priority: "high",
      due_date: Date.today + 3
    )

    CapaAssignment.create!(capa: matching_capa, company_user: @assignee_company_user)
    matching_action = CapaAction.create!(
      capa: matching_capa,
      title: "Matching Action",
      action_type: "Corrective",
      status: "Started",
      due_date: Date.today + 2
    )
    CapaActionAssignment.create!(capa_action: matching_action, company_user: @assignee_company_user)

    non_matching_priority = Capa.create!(
      company: @company,
      title: "Wrong Priority",
      description: "Excluded by priority",
      source: "audit",
      status: "assigned",
      priority: "medium",
      due_date: Date.today + 3
    )

    CapaAssignment.create!(capa: non_matching_priority, company_user: @assignee_company_user)
    other_action = CapaAction.create!(
      capa: non_matching_priority,
      title: "Other Action",
      action_type: "Preventive",
      status: "Started",
      due_date: Date.today + 3
    )
    CapaActionAssignment.create!(capa_action: other_action, company_user: @assignee_company_user)

    outside_date = Capa.create!(
      company: @company,
      title: "Outside Date",
      description: "Excluded by date",
      source: "audit",
      status: "assigned",
      priority: "high",
      due_date: Date.today + 10
    )

    CapaAssignment.create!(capa: outside_date, company_user: @second_company_user)
    late_action = CapaAction.create!(
      capa: outside_date,
      title: "Late Action",
      action_type: "Corrective",
      status: "Started",
      due_date: Date.today + 10
    )
    CapaActionAssignment.create!(capa_action: late_action, company_user: @second_company_user)

    get dashboard_export_capas_path, params: {
      status: "assigned",
      priority: "high",
      due_date_from: Date.today.to_s,
      due_date_to: (Date.today + 5).to_s,
      assignee_ids: [@assignee_company_user.id],
      archived_state: "all"
    }

    assert_response :success
    assert_equal ["Target CAPA"], exported_titles
    assert_equal ["Matching Action"], exported_action_titles
  end

  test "regenerate_root_cause blocks when user lacks credits" do
    AiActionCredit.find_by(action_type: "REGENERATE_ROOT_CAUSE").update!(credit_cost: 3)
    CreditService.clear_cache
    @company_user.update!(assigned_credits: 1)

    CapaQuestionnaireService.stub :new, ->(_capa) { Minitest::Mock.new } do
      post regenerate_root_cause_path, as: :json
    end

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_includes body["error"], "credits"
    assert_equal 1, @company_user.reload.assigned_credits
  end

  test "regenerate_root_cause deducts credits when successful" do
    AiActionCredit.find_by(action_type: "REGENERATE_ROOT_CAUSE").update!(credit_cost: 2)
    CreditService.clear_cache
    @company_user.update!(assigned_credits: 5)

    stubbed_service = Minitest::Mock.new
    stubbed_service.expect(:generate_root_cause_summary, "New root cause", [Questionnaire])

    CapaQuestionnaireService.stub :new, ->(capa_arg) {
      assert_equal @capa, capa_arg
      stubbed_service
    } do
      post regenerate_root_cause_path, as: :json
    end

    stubbed_service.verify
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal "New root cause", body["root_cause"]
    assert_equal 3, @company_user.reload.assigned_credits
  end

  test "update_status removes assignments when moving assigned to open" do
    patch "/dashboard/capa_management/#{@capa.id}/status", params: { status: 'open' }, as: :json
    assert_response :success

    body = JSON.parse(response.body)
    assert_includes body["notification_html"], "All assigned users were removed"

    @capa.reload
    assert_equal 'open', @capa.status
    assert_equal 0, @capa.capa_assignments.count
  end

  test "update removes assignments when status set to open" do
    patch "/dashboard/capa_management/#{@capa.id}", params: { capa: { status: 'open' } }, as: :json
    assert_response :success

    body = JSON.parse(response.body)
    assert_includes body["notification_html"], "All assigned users were removed"

    @capa.reload
    assert_equal 'open', @capa.status
    assert_equal 0, @capa.capa_assignments.count
  end

  test "generate_actions requires questionnaire" do
    @capa.questionnaire.destroy!
    @company_user.update!(assigned_credits: 20)

    post generate_actions_path, as: :json

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_includes body["error"].downcase, "questionnaire"
  end

  test "generate_actions requires root cause" do
    @questionnaire.update!(root_cause: nil)
    @company_user.update!(assigned_credits: 20)

    post generate_actions_path, as: :json

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_includes body["error"].downcase, "root cause"
  end

  test "generate_actions succeeds when questionnaire and root cause exist" do
    AiActionCredit.find_by(action_type: "GENERATE_CAPA_ACTIONS").update!(credit_cost: 5)
    CreditService.clear_cache
    @company_user.update!(assigned_credits: 20)

    stubbed_service = Minitest::Mock.new
    stubbed_service.expect(:generate, {
      "actions" => [
        { "title" => "Auto Action", "action_type" => "corrective", "notes" => "Test note" }
      ]
    })

    CapaActionGenerationService.stub :new, ->(capa_arg) {
      assert_equal @capa, capa_arg
      stubbed_service
    } do
      post generate_actions_path, as: :json
    end

    stubbed_service.verify

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body["actions_count"]
    assert_equal 15, @company_user.reload.assigned_credits
    assert_equal 1, @capa.reload.capa_actions.count
  end

  private

  def regenerate_root_cause_path
    "/dashboard/capa_management/#{@capa.id}/questionnaire/regenerate_root_cause"
  end

  def generate_actions_path
    "/dashboard/capa_management/#{@capa.id}/generate_actions"
  end

  def exported_titles
    csv_body = read_zip_entry("capas.csv").sub("\xEF\xBB\xBF", "")
    rows = CSV.parse(csv_body)
    rows.drop(1).map { |row| row[1] }
  end

  def exported_action_titles
    csv_body = read_zip_entry("actions.csv").sub("\xEF\xBB\xBF", "")
    rows = CSV.parse(csv_body)
    rows.drop(1).map { |row| row[1] }
  end

  def read_zip_entry(entry_name)
    body = response.body
    body = body.string if body.respond_to?(:string)
    body = body.to_s unless body.is_a?(String)
    content = nil
    Zip::File.open_buffer(body) do |zip|
      data = zip.find_entry(entry_name).get_input_stream.read
      data = data.string if data.respond_to?(:string)
      content = data.to_s.dup.force_encoding("UTF-8")
    end
    content
  end
end

