require "test_helper"
require "minitest/mock"

# Every movement in the product that concerns someone other than the actor
# tells that person. One test per movement, checking who is told; plus the
# inventory: every kind has a title in both languages and shows on the bell.
class NotificationCoverageTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    Rails.application.reload_routes!
    @company = Company.create!(name: "Notify Co #{SecureRandom.hex(4)}", license_seats: 10, credits: 10, is_active: true)
    @admin = person("admin", :company_admin)
    @qm = person("qm", :company_quality_manager)
    @qm.company_user.update!(pp_manager: true)
    @rm = person("rm", :company_risk_manager)
    @rm.company_user.update!(gov_manager: true)
    @contrib = person("contrib", :company_contributor)
    @head = person("head", :company_contributor)
    @unit = @company.org_units.create!(name_en: "Quality", level: 1, head_user: @head)
    @contrib.update!(org_unit: @unit)
    @super_admin = User.create!(email: "root-#{SecureRandom.hex(4)}@example.com", password: "Password1234",
      password_confirmation: "Password1234", name: "Root", role: "super_admin", is_active: true)
  end

  def person(prefix, role)
    user = User.create!(email: "#{prefix}-#{SecureRandom.hex(4)}@example.com", password: "Password1234",
      password_confirmation: "Password1234", name: prefix.humanize, is_active: true, receive_notifications_on_email: true)
    CompanyUser.create!(company: @company, user: user, role: CompanyUser::ROLES[role])
    user
  end

  def told?(user, kind, source: nil)
    scope = Notification.where(recipient: user, kind: kind)
    scope = scope.where(source: source) if source
    scope.exists?
  end

  # ---- inventory ---------------------------------------------------------

  test "every notification kind has a title in English and Arabic" do
    Notification::KINDS.each do |kind|
      %i[en ar].each do |locale|
        assert I18n.exists?("user_notifications.#{kind}_title", locale), "#{kind} has no #{locale} title"
      end
    end
  end

  test "the bell page renders every kind and an email goes out for people who asked for email" do
    record = @company.pp_records.create!(record_type: "policy", title_en: "Bell", description: "x")
    assert_enqueued_emails Notification::KINDS.size do
      Notification::KINDS.each do |kind|
        Notification.create!(recipient: @contrib, kind: kind, title: "Title for #{kind}", link_path: "/dashboard/overview", source: record)
      end
    end
    @contrib.update!(receive_notifications_on_email: false)
    assert_no_enqueued_emails { Notification.create!(recipient: @contrib, kind: "record_published", title: "quiet", link_path: "/") }

    sign_in @contrib
    # The bell pages by 25; read every page.
    pages = ""
    (1..3).each do |page|
      get dashboard_notifications_path(page: page)
      assert_response :success
      pages << response.body.squish
    end
    Notification.where(recipient: @contrib).find_each do |n|
      shown = n.title_in_locale(:en).to_s
      assert shown.present?, "#{n.kind} renders an empty title"
      assert_includes pages, CGI.escapeHTML(shown).squish.first(30), "#{n.kind} is not on the bell page"
    end
  end

  # ---- Documenter --------------------------------------------------------

  test "documenter: verification, correction, return, approvals, hand-outs, comments and publication all notify" do
    record = @company.pp_records.create!(record_type: "policy", title_en: "Notify Policy", description: "x",
      owner_user: @qm, owner_org_unit: @unit, verifier_user: @contrib)

    # correction request → owner; return of the corrected record → verifier
    sign_in @contrib
    post dashboard_documenter_request_correction_path(record), params: { reason: "Add scope" }
    assert told?(@qm, "record_correction_requested", source: record)
    sign_in @qm
    post dashboard_documenter_submit_task_path(record)
    assert told?(@contrib, "record_task_submitted", source: record)

    # verified → next stage is the P&P manager's: manager told (verifier moved it), owner is the manager here
    sign_in @contrib
    post dashboard_documenter_advance_record_path(record)
    assert_equal "s1_approved", record.reload.stage_key
    assert told?(@qm, "record_stage_entered", source: record)

    # manager approves → preparation belongs to the unit head: head told
    sign_in @qm
    post dashboard_documenter_advance_record_path(record)
    assert_equal "s2_prep", record.reload.stage_key
    assert told?(@head, "record_stage_entered", source: record)

    # head hands the draft to a reporter → reporter told; reporter sends back → head told
    sign_in @head
    post dashboard_documenter_assign_task_path(record), params: { user_id: @contrib.id, note: "Write it" }
    assert told?(@contrib, "record_task_assigned", source: record)
    sign_in @contrib
    post dashboard_pp_record_clauses_path(record), params: { pp_record_clause: { title: "Scope", body: "All" } }
    post dashboard_documenter_submit_task_path(record)
    assert told?(@head, "record_task_submitted", source: record)

    # a manager comments on a clause → owner/holders told; resolving → commenter told
    clause = record.clauses.first
    sign_in @admin
    post dashboard_pp_record_clause_comments_path(record, clause), params: { body: "Tighten it" }
    assert told?(@qm, "record_comment_added", source: record)
    sign_in @qm
    patch dashboard_pp_record_resolve_comment_path(record, clause.comments.first)
    assert told?(@admin, "record_comment_resolved", source: record)

    # head approves the draft → draft review is the manager's
    sign_in @head
    post dashboard_documenter_advance_record_path(record)
    assert_equal "s2_draftReview", record.reload.stage_key
    assert told?(@qm, "record_stage_entered", source: record)

    # manager returns it → head told with the reason
    sign_in @qm
    post dashboard_documenter_return_path, params: { record_id: record.id, stage_key: "s2_prep", reason: "Missing scope" }
    assert_equal "s2_prep", record.reload.stage_key
    returned = Notification.where(recipient: @head, kind: "record_returned", source: record).last
    assert returned
    assert_includes returned.title, "Missing scope"
  end

  test "documenter: approval requests, rejections and publication notify" do
    record = @company.pp_records.create!(record_type: "policy", title_en: "Approve Me", description: "x",
      owner_user: @qm, owner_org_unit: @unit, current_stage: "s2_stakeholders")
    other_unit = @company.org_units.create!(name_en: "Legal", level: 1, head_user: @rm)

    sign_in @qm
    post dashboard_documenter_request_approvals_path(record), params: { org_unit_ids: [ other_unit.id ] }
    assert told?(@rm, "record_approval_requested", source: record)

    approval = record.stage_approvals.first
    sign_in @rm
    patch dashboard_documenter_answer_approval_path(approval_id: approval.id), params: { decision: "rejected", comment: "No" }
    assert told?(@qm, "record_approval_rejected", source: record)

    glossary = @company.pp_records.create!(record_type: "glossary", title_en: "Term", description: "def", current_stage: "g1_submitted")
    sign_in @qm
    RecordPublisher.new(glossary, by: @qm, company: @company).publish!
    assert told?(@contrib, "record_published", source: glossary)
  end

  # ---- Authorities -------------------------------------------------------

  test "authorities: review requested and answered, comments and answers, publication" do
    matrix = AuthorityMatrixVersionService.first_version(@company, actor: @admin)
    category = @company.authority_categories.create!(name_en: "Cat")
    authority = @company.authorities.create!(matrix: matrix, authority_category: category, name_en: "Sign")

    sign_in @admin
    post dashboard_send_authority_review_path(matrix_id: matrix.id), params: { user_ids: [ @qm.id ] }
    assert told?(@qm, "authority_review_requested", source: matrix)

    sign_in @qm
    post dashboard_create_authority_review_comment_path(authority_id: authority.id, matrix_id: matrix.id), params: { body: "Who signs?" }
    assert told?(@admin, "authority_comment_added", source: matrix)
    assert told?(@rm, "authority_comment_added", source: matrix)

    sign_in @admin
    comment = matrix.review_comments.first
    patch dashboard_answer_authority_review_comment_path(comment, matrix_id: matrix.id), params: { decision: "accepted", reply: "The CEO" }
    assert told?(@qm, "authority_comment_answered", source: matrix)

    sign_in @qm
    review = matrix.matrix_reviews.first
    patch dashboard_answer_authority_review_path(review, matrix_id: matrix.id), params: { decision: "accepted" }
    assert told?(@admin, "authority_review_answered", source: matrix)

    sign_in @admin
    post dashboard_publish_authority_matrix_path(matrix_id: matrix.id)
    assert told?(@contrib, "authority_matrix_published", source: matrix)
    assert_not told?(@admin, "authority_matrix_published", source: matrix), "the publisher is not told about their own act"
  end

  # ---- Governance --------------------------------------------------------

  test "governance: assignment, submission, acceptance, risk acceptance, vendor sign-off and approval" do
    sign_in @rm
    post dashboard_customer_commitments_path, params: { customer_commitment: { title: "Deliver", customer_name: "Bank",
      due_date: 3.days.from_now.to_date, owner_id: @contrib.company_user.id } }
    commitment = CustomerCommitment.find_by(title: "Deliver")
    assert told?(@contrib, "governance_task_assigned", source: commitment)

    sign_in @contrib
    post dashboard_submit_commitment_task_path(commitment), params: { fulfillment_note: "Done" }
    assert told?(@rm, "governance_task_submitted", source: commitment)

    sign_in @rm
    patch acceptance_dashboard_customer_commitment_path(commitment), params: { acceptance_status: "accepted" }
    assert told?(@contrib, "commitment_acceptance_recorded", source: commitment)

    risk = Risk.create!(company: @company, title: "Big risk", cause: "c", event: "e", impact_statement: "i", likelihood: 5, impact: 5,
      status: "identified", owner: @qm.company_user, created_by: @rm, control_owner: @contrib.company_user, treatment_plan: "Plan")
    patch dashboard_accept_risk_path(risk), params: { acceptance_rationale: "Accepted for now", acceptance_expires_on: 1.month.from_now.to_date }
    assert told?(@qm, "risk_accepted", source: risk)
    assert told?(@contrib, "risk_accepted", source: risk)

    vendor = Vendor.create!(company: @company, name: "Supplier", created_by: @rm, criticality: "high")
    post dashboard_vendor_assessments_path(vendor), params: { vendor_assessment: { assessed_on: "2026-09-01", rationale: "Reviewed",
      next_review_on: "2027-03-01", scores: VendorAssessment::CRITERIA.index_with { 4 } } }
    assessment = vendor.assessments.first
    sign_in @admin
    patch sign_off_dashboard_vendor_assessment_path(vendor, assessment), params: { review_note: "ok" }
    assert told?(@rm, "vendor_assessment_signed_off", source: vendor)
    patch approval_dashboard_vendor_path(vendor), params: { approval_status: "approved", approval_note: "fine" }
    assert told?(@rm, "vendor_approval_recorded", source: vendor)
  end

  # ---- CAPA --------------------------------------------------------------

  test "capa: assignment, action assignment, evidence, comments, review round and closure" do
    sign_in @qm
    post "/dashboard/capa_management", params: { capa: { title: "Late", description: "d", source: "audit", priority: "medium",
      company_user_ids: [ @contrib.company_user.id ] } }
    capa = Capa.order(:created_at).last
    assert told?(@contrib, "capa_assigned", source: capa)

    post dashboard_create_capa_action_path(capa_id: capa.id), params: { capa_action: { title: "Fix it", action_type: "corrective",
      status: "started", company_user_ids: [ @contrib.company_user.id ] } }
    action = capa.capa_actions.first
    assert action, "the action was created"
    assert told?(@contrib, "capa_action_assigned", source: capa)

    sign_in @contrib
    post dashboard_create_capa_action_comment_path(capa_id: capa.id, id: action.id), params: { comment: { body: "Working on it" } }, as: :json
    assert told?(@qm, "capa_action_comment_added", source: capa)
    post dashboard_submit_capa_action_review_path(capa, action)
    assert told?(@qm, "capa_action_submitted", source: capa)

    sign_in @qm
    post dashboard_review_capa_action_path(capa, action), params: { outcome: "done" }
    assert told?(@contrib, "capa_action_accepted", source: capa)

    patch dashboard_update_capa_status_path(capa), params: { status: "closed" }, as: :json
    assert_equal "closed", capa.reload.status
    assert told?(@contrib, "capa_closed", source: capa)
  end

  # ---- Account -----------------------------------------------------------

  test "account: role, designation, status, leave cover and email change all tell the person" do
    sign_in @super_admin
    patch dashboard_change_user_role_path(@contrib), params: { company_role: "company_auditor" }, as: :json
    assert told?(@contrib, "account_role_changed")

    patch dashboard_update_user_status_path(@contrib), params: { is_active: false }, as: :json
    assert told?(@contrib, "account_status_changed")

    sign_in @admin
    patch dashboard_toggle_gov_manager_path(@rm)
    assert told?(@rm, "account_designation_changed")

    sign_in @contrib
    @contrib.update!(is_active: true)
    patch dashboard_update_delegation_path, params: { user: { delegate_user_id: @head.id, delegate_from: Date.current } }
    assert told?(@head, "delegation_cover_assigned")
  end
end
