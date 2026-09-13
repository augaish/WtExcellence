require "test_helper"

# Deployment retest N01–N06.
class Dashboard::RetestFixesTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!
    @company = Company.create!(name: "Retest Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @qm = create_user("qm", CompanyUser::ROLES[:company_quality_manager])
    @contributor = create_user("contrib", CompanyUser::ROLES[:company_contributor])
    @rm = create_user("rm", CompanyUser::ROLES[:company_risk_manager])
  end

  def create_user(prefix, role)
    user = User.create!(email: "#{prefix}-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: prefix.humanize, is_active: true)
    CompanyUser.create!(company: @company, user: user, role: role)
    user
  end

  test "N01: a file stored on disk is streamed by the app and opens" do
    upload = Upload.new(company_id: @company.id, filename: "policy.pdf", name: "policy.pdf", mime_type: "application/pdf",
      size_bytes: 4, uploaded_by: @qm.id, visibility: "public")
    upload.file.attach(io: StringIO.new("%PDF"), filename: "policy.pdf", content_type: "application/pdf")
    upload.save!
    assert upload.served_by_app?
    assert_equal download_folder_uploads_upload_path(folder_id: "all", id: upload.id, disposition: "inline"), upload.file_url(disposition: "inline")

    sign_in @contributor
    get upload.file_url(disposition: "inline")
    assert_response :success
    assert_equal "application/pdf", response.media_type
    assert_equal "%PDF", response.body
  end

  test "N05: creating a CAPA writes one creation entry" do
    sign_in @qm
    post "/dashboard/capa_management", params: { capa: { title: "Once", description: "d", source: "audit", priority: "medium" } }
    capa = Capa.order(:created_at).last
    assert_equal [ "CREATE_CAPA" ], AuditLog.where(entity_id: capa.id).pluck(:action)
  end

  test "N03: the owner returns the corrected record and the verifier then advances; N06 names the system for automatic moves" do
    record = @company.pp_records.create!(record_type: "policy", title_en: "Correction Probe", description: "x",
      owner_user: @qm, verifier_user: @contributor)
    sign_in @contributor
    post dashboard_documenter_request_correction_path(record), params: { reason: "Add the evidence reference" }

    post dashboard_documenter_advance_record_path(record)
    assert_equal "s1_verify", record.reload.stage_key, "the verifier cannot advance while the owner still has the correction"
    get dashboard_documenter_record_path(record)
    assert_includes response.body, CGI.escapeHTML(I18n.t("documenter.waiting_for_correction", name: @qm.name))

    sign_in @qm
    get dashboard_documenter_record_path(record)
    assert_includes response.body, CGI.escapeHTML(I18n.t("documenter.correction_requested_by", name: @contributor.name))
    assert_select "input[type=submit][value=?]", I18n.t("documenter.actions.return_to_verifier")
    post dashboard_documenter_submit_task_path(record), params: { note: "Reference added" }
    assert Notification.exists?(recipient: @contributor, kind: "record_task_submitted")

    sign_in @contributor
    post dashboard_documenter_advance_record_path(record)
    assert_equal "s1_approved", record.reload.stage_key

    record.stage_transitions.create!(from_stage: "s1_approved", to_stage: "s2_prep", direction: "forward", actor_user: nil)
    get dashboard_documenter_record_path(record)
    assert_includes response.body, I18n.t("documenter.system_actor")
  end

  test "N02: the risk page shows the control owner's report where the manager's notification lands" do
    risk = Risk.create!(company: @company, title: "Continuity", cause: "c", event: "e", impact_statement: "i", likelihood: 3, impact: 3,
      status: "identified", owner: @rm.company_user, created_by: @rm, control_owner: @contributor.company_user, treatment_plan: "Plan")
    sign_in @contributor
    post dashboard_submit_control_task_path(risk), params: { control_evidence_note: "Backup supplier contracted" }

    sign_in @rm
    notification = Notification.find_by(recipient: @rm, kind: "governance_task_submitted")
    get notification.link_path
    assert_response :success
    assert_includes response.body, "Backup supplier contracted"
    assert_includes response.body, CGI.escapeHTML(I18n.t("governance_tasks.control_report_title"))
  end
end
