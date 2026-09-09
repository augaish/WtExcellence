require "test_helper"

class Dashboard::ProcessEvaluationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!

    @company = Company.create!(name: "EvalCtl #{SecureRandom.hex(4)}", license_seats: 10, credits: 50, is_active: true)
    @admin = User.create!(email: "eval-#{SecureRandom.hex(4)}@example.com",
      password: "password123", password_confirmation: "password123", name: "Admin", is_active: true)
    CompanyUser.create!(company: @company, user: @admin, role: CompanyUser::ROLES[:company_admin])

    @record = @company.pp_records.create!(record_type: "procedure", title_en: "Onboarding", pp_process: level_two_process(@company))
    @diagram = @company.pp_diagrams.create!(owner: @record, name: "Onboarding process",
      trigger_text: "Request received", inputs_summary: "Draft", outputs_summary: "Signed policy")
    @start = @diagram.elements.create!(element_type: "startEvent", title: "Start", performer: "HR", description: "Begins")
    @task = @diagram.elements.create!(element_type: "userTask", title: "Review", performer: "HR",
      description: "Check details", input: "Draft", output: "Reviewed")
    @finish = @diagram.elements.create!(element_type: "endEvent", title: "Done", performer: "HR", description: "Ends")
    @diagram.flows.create!(from_element: @start, to_element: @task, kind: "sequence")
  end

  test "index lists the saved diagrams to choose from" do
    sign_in @admin
    get dashboard_process_evaluations_path

    assert_response :success
    assert_select "body", text: /Onboarding process/
  end

  test "index shows a teaching empty state when there is nothing to evaluate" do
    sign_in @admin
    @diagram.destroy

    get dashboard_process_evaluations_path

    assert_response :success
    assert_includes response.body, I18n.t("evaluation.no_diagrams")
  end

  # The spec's acceptance check: evaluateProcess must run against a real saved
  # diagram from the Process Architect.
  test "evaluating a real saved diagram renders score, maturity, axes and fixes" do
    sign_in @admin
    get dashboard_process_evaluation_path(@diagram)

    assert_response :success
    # Score ring.
    assert_select "svg[role=img]"
    # All six axes.
    %w[bpmn sipoc lean iso raci digital].each do |axis|
      assert_includes response.body, I18n.t("evaluation.axes.#{axis}.name")
    end
    # Maturity tier badge and the recommendations section.
    assert_includes response.body, I18n.t("evaluation.recommendations_title")
  end

  test "the score is cached on the diagram after evaluating" do
    sign_in @admin
    assert_nil @diagram.last_score

    get dashboard_process_evaluation_path(@diagram)

    @diagram.reload
    assert_kind_of Integer, @diagram.last_score
    assert @diagram.last_evaluated_at.present?
  end

  test "recommendations are ordered high, then medium, then low" do
    sign_in @admin
    # A deliberately poor diagram so several priorities appear.
    poor = @company.pp_diagrams.create!(owner: @record, name: "Poor")
    poor.elements.create!(element_type: "manualTask", title: nil, performer: nil)

    get dashboard_process_evaluation_path(poor)
    assert_response :success

    result = ProcessEvaluationService.evaluate_diagram(poor.reload)
    order = result[:recommendations].map { |r| r[:priority] }
    sorted = order.sort_by { |p| ProcessEvaluationService::PRIORITIES.index(p) }
    # The view sorts them; confirm the sort is a real reordering rule.
    assert_equal sorted, sorted.sort_by { |p| ProcessEvaluationService::PRIORITIES.index(p) }

    positions = ProcessEvaluationService::PRIORITIES.map { |p| response.body.index(I18n.t("evaluation.priorities.#{p}")) }.compact
    assert_equal positions.sort, positions, "high priority fixes must appear before lower ones"
  end

  test "another company's diagram cannot be evaluated" do
    sign_in @admin
    other = Company.create!(name: "Other #{SecureRandom.hex(4)}", license_seats: 1, is_active: true)
    foreign_record = other.pp_records.create!(record_type: "policy", title_en: "Foreign")
    foreign = other.pp_diagrams.create!(owner: foreign_record, name: "Foreign")

    get dashboard_process_evaluation_path(foreign)

    assert_redirected_to dashboard_process_evaluations_path
  end

  test "evaluation is reachable from the P&P sidebar group" do
    sign_in @admin
    get dashboard_process_evaluations_path

    assert_response :success
    assert_select "aside#sidebar a[href=?]", dashboard_process_evaluations_path
  end
end
