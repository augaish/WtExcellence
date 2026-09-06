require "test_helper"

class AssessmentsControllerTest < ActionDispatch::IntegrationTest
  # Ensure Devise mappings are loaded before sign_in is called.
  # In integration tests, routes (and thus Devise mappings) are loaded lazily
  # on the first HTTP request. Without this, sign_in fails with
  # "Could not find a valid mapping" if called before any request.
  setup do
    Rails.application.reload_routes!
    @company = Company.create!(
      name: "Assessment Co #{SecureRandom.hex(4)}",
      license_seats: 10,
      credits: 100,
      is_active: true
    )

    @admin_user = User.create!(
      email: "assess-admin-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "Admin User",
      is_active: true
    )
    CompanyUser.create!(company: @company, user: @admin_user, role: CompanyUser::ROLES[:company_admin])

    @viewer_user = User.create!(
      email: "assess-viewer-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "Viewer User",
      is_active: true
    )
    CompanyUser.create!(company: @company, user: @viewer_user, role: CompanyUser::ROLES[:company_viewer])

    # Standard + clause hierarchy
    @standard = Standard.create!(code: "EFQM-#{SecureRandom.hex(4)}")
    @version = StandardVersion.create!(standard: @standard, version_label: "2020", status: "published")

    # Link company to standard (required for authorization)
    CompanyStandard.create!(company: @company, standard: @standard, status: "active", active_version_id: @version.id)

    @parent_clause = Clause.create!(standard_version: @version, code: "1", sort_order: 0)
    @terminal_clause = Clause.create!(
      standard_version: @version, code: "1.1", sort_order: 0,
      parent: @parent_clause, allocated_points: 100
    )
    @sibling_clause = Clause.create!(
      standard_version: @version, code: "1.2", sort_order: 1,
      parent: @parent_clause, allocated_points: 100
    )

    # Tool with EFQM structure
    @tool = Tool.create!(name: "Assess Tool #{SecureRandom.hex(4)}", description: "Test EFQM")
    @cp1 = ToolCheckpoint.create!(tool: @tool, name: "Approach", display_order: 1)
    @sub1 = ToolSubcheckpoint.create!(
      tool_checkpoint: @cp1, name: "Sound", scoring_type: "Percentage",
      weight: 0.5, is_cap: true, display_order: 1, description: "Well-reasoned approach"
    )
    @sub2 = ToolSubcheckpoint.create!(
      tool_checkpoint: @cp1, name: "Aligned", scoring_type: "Percentage",
      weight: 0.5, is_cap: false, display_order: 2
    )

    # Link tool to clauses
    @tool_clause = ToolClause.create!(tool: @tool, clause: @terminal_clause)
    ToolClause.create!(tool: @tool, clause: @sibling_clause)

    # Checklist item
    @checklist_item = ChecklistItem.create!(
      clause: @terminal_clause, item_type: "requirement",
      code: "1.1a", sort_order: 0
    )
  end

  # ========= AC-A1: Navigation to assessment page =========

  test "authenticated admin can access assessment page for terminal clause" do
    sign_in @admin_user
    get clause_assessment_path(@terminal_clause)
    assert_response :success
  end

  test "unauthenticated user is redirected to sign in" do
    get clause_assessment_path(@terminal_clause)
    assert_response :redirect
    assert_redirected_to new_user_session_path
  end

  # ========= AC-A2: Page content =========

  test "assessment page displays clause code" do
    sign_in @admin_user
    get clause_assessment_path(@terminal_clause)
    assert_response :success
    assert_match "1.1", response.body
  end

  test "assessment page shows tool name" do
    sign_in @admin_user
    get clause_assessment_path(@terminal_clause)
    assert_match @tool.name, response.body
  end

  # ========= AC-A5/A6: Text areas match tool categories =========

  test "assessment page renders text area labels matching tool checkpoints" do
    sign_in @admin_user
    get clause_assessment_path(@terminal_clause)
    assert_match "Approach", response.body
  end

  # ========= AC-A7: Character limit =========

  test "text areas have maxlength 100" do
    sign_in @admin_user
    get clause_assessment_path(@terminal_clause)
    assert_select "textarea[maxlength='100']"
  end

  # ========= EC-2.4: Non-terminal clause redirects =========

  test "non-terminal clause redirects away" do
    sign_in @admin_user
    get clause_assessment_path(@parent_clause)
    assert_response :redirect
  end

  # ========= EC-2.6: Viewer gets read-only mode =========

  test "viewer sees assessment page without save buttons" do
    sign_in @viewer_user
    get clause_assessment_path(@terminal_clause)
    assert_response :success
    # Viewer should not see action buttons
    assert_no_match "save_draft", response.body
    assert_no_match "submit_for_review", response.body
  end

  # ========= AC-C1: Scoring section renders groups =========

  test "scoring section renders attribute names" do
    sign_in @admin_user
    get clause_assessment_path(@terminal_clause)
    assert_match "Sound", response.body
    assert_match "Aligned", response.body
  end

  # ========= AC-C2: Percentage sliders =========

  test "scoring section renders range inputs for percentage attributes" do
    sign_in @admin_user
    get clause_assessment_path(@terminal_clause)
    assert_select "input[type='range']"
  end

  # ========= AC-C4: CAP badge =========

  test "CAP badge shown for capped attribute" do
    sign_in @admin_user
    get clause_assessment_path(@terminal_clause)
    assert_match "CAP", response.body
  end

  # ========= AC-C3: Tooltip =========

  test "tooltip description present for attribute with description" do
    sign_in @admin_user
    get clause_assessment_path(@terminal_clause)
    assert_match "Well-reasoned approach", response.body
  end

  # ========= AC-A11: Save Draft persists scores =========

  test "save draft persists scores and summaries" do
    sign_in @admin_user

    patch update_clause_assessment_path(@terminal_clause), params: {
      assessment: {
        scores: { @sub1.id => "65", @sub2.id => "70" },
        checkpoint_summaries: {
          @checklist_item.id => { @sub1.tool_checkpoint.id => "Test approach text" }
        },
        commit: "save_draft"
      }
    }

    assert_redirected_to clause_assessment_path(@terminal_clause)

    score = assessment_score_for(@sub1)
    assert score.present?, "An AssessmentScore should be created"
    assert_in_delta 65.0, score.percentage_score.to_f, 0.01

    summary = CheckpointSummary.find_by(
      tool_clause: @tool_clause, checklist_item_id: @checklist_item.id,
      tool_checkpoint_id: @sub1.tool_checkpoint.id, company: @company
    )
    assert_equal "Test approach text", summary&.summary
  end

  test "save draft transitions not_started containers to in_drafts" do
    sign_in @admin_user

    patch update_clause_assessment_path(@terminal_clause), params: {
      assessment: {
        scores: { @sub1.id => "50" },
        commit: "save_draft"
      }
    }

    assert_equal "in_drafts", assessment_record.status
  end

  # ========= AC-A12: Submit for Review =========

  test "submit for review transitions status to under_review" do
    sign_in @admin_user

    patch update_clause_assessment_path(@terminal_clause), params: {
      assessment: {
        scores: { @sub1.id => "80", @sub2.id => "75" },
        commit: "submit_for_review"
      }
    }

    assert_redirected_to clause_assessment_path(@terminal_clause)

    assert_equal "under_review", assessment_record.status
  end

  # ========= Viewer cannot update =========

  test "viewer cannot update assessment scores" do
    sign_in @viewer_user

    # First visit the page (which eagerly creates empty containers)
    get clause_assessment_path(@terminal_clause)

    patch update_clause_assessment_path(@terminal_clause), params: {
      assessment: {
        scores: { @sub1.id => "99" },
        commit: "save_draft"
      }
    }

    # Viewer should be blocked (redirect for HTML, 403 for JSON format)
    assert_includes [ 302, 403 ], response.status

    # The assessment may exist (created by the page load) but no score may be set.
    assert_nil assessment_score_for(@sub1)&.percentage_score,
      "Viewer should not be able to set scores"
  end

  # ========= EC-2.5: No tool linked =========

  test "assessment page with no tool linked shows info message" do
    bare_clause = Clause.create!(
      standard_version: @version, code: "3.1", sort_order: 2,
      allocated_points: 50
    )

    sign_in @admin_user
    get clause_assessment_path(bare_clause)
    assert_response :success
    assert_match I18n.t("assessments.no_tool_linked"), response.body
  end

  # ========= Overall score bar =========

  test "overall score bar elements are rendered" do
    sign_in @admin_user
    get clause_assessment_path(@terminal_clause)
    assert_select "[data-scoring-calculator-target='overallBar']"
    assert_select "[data-scoring-calculator-target='overallValue']"
  end

  # ========= Stimulus controller wiring =========

  test "scoring calculator controller is wired up" do
    sign_in @admin_user
    get clause_assessment_path(@terminal_clause)
    assert_select "[data-controller='scoring-calculator']"
  end

  private

  # Scores and status live on Assessment / AssessmentScore (one assessment per
  # tool_clause + company); summaries live on CheckpointSummary.
  def assessment_record
    Assessment.find_by(tool_clause: @tool_clause, company: @company)
  end

  def assessment_score_for(subcheckpoint)
    assessment_record&.assessment_scores&.find_by(tool_subcheckpoint: subcheckpoint)
  end
end
