require "test_helper"

# Risk/DoA round, group 2: assessments returned for rework, reviewers told,
# evidence from the Library and the device, supplier on risks.
class RiskDoaRoundGroup2Test < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!
    @company = Company.create!(name: "R2 Co #{SecureRandom.hex(4)}", license_seats: 10, credits: 10, is_active: true)
    @admin = person("admin", :company_admin)
    @rm = person("rm", :company_risk_manager)
    @rm2 = person("rm2", :company_risk_manager)
    @vendor = Vendor.create!(company: @company, name: "Cloud Host", created_by: @rm)
    @upload = Upload.new(company_id: @company.id, filename: "soc2.pdf", name: "SOC 2 report", mime_type: "application/pdf", size_bytes: 4, uploaded_by: @rm.id, visibility: "public")
    @upload.file.attach(io: StringIO.new("%PDF"), filename: "soc2.pdf", content_type: "application/pdf")
    @upload.save!
  end

  def person(prefix, role)
    user = User.create!(email: "#{prefix}-#{SecureRandom.hex(4)}@example.com", password: "Password1234",
      password_confirmation: "Password1234", name: prefix.humanize, is_active: true)
    CompanyUser.create!(company: @company, user: user, role: CompanyUser::ROLES[role])
    user
  end

  def scores(n) = VendorAssessment::CRITERIA.index_with { n }

  test "an assessment tells the reviewers, is returned with a reason, corrected with new evidence and signed off" do
    sign_in @rm
    file = Rack::Test::UploadedFile.new(StringIO.new("%PDF-1"), "application/pdf", original_filename: "iso-cert.pdf")
    post dashboard_vendor_assessments_path(@vendor), params: {
      vendor_assessment: { assessed_on: "2026-09-01", rationale: "First look", scores: scores(3) },
      upload_ids: [ @upload.id ], files: [ file ] }
    assessment = @vendor.assessments.sole
    assert_equal [ "SOC 2 report", "iso-cert.pdf" ].sort, assessment.uploads.map(&:display_name).sort
    assert Notification.exists?(recipient: @rm2, kind: "vendor_assessment_submitted")
    assert Notification.exists?(recipient: @admin, kind: "vendor_assessment_submitted")
    assert_not Notification.exists?(recipient: @rm, kind: "vendor_assessment_submitted"), "the assessor is not told about their own work"

    sign_in @rm2
    get dashboard_vendor_path(@vendor)
    assert_select "form[action=?]", return_for_rework_dashboard_vendor_assessment_path(@vendor, assessment)
    patch return_for_rework_dashboard_vendor_assessment_path(@vendor, assessment), params: { return_reason: "" }
    assert_not assessment.reload.returned?, "a reason is required"
    patch return_for_rework_dashboard_vendor_assessment_path(@vendor, assessment), params: { return_reason: "Continuity score ignores the DR test" }
    assert assessment.reload.returned?
    assert Notification.exists?(recipient: @rm, kind: "vendor_assessment_returned")

    sign_in @rm
    get dashboard_vendor_path(@vendor)
    assert_includes response.body, "Continuity score ignores the DR test"
    patch dashboard_vendor_assessment_path(@vendor, assessment), params: {
      vendor_assessment: { assessed_on: "2026-09-01", rationale: "DR test reviewed", scores: scores(4) } }
    assessment.reload
    assert_not assessment.returned?
    assert_equal "DR test reviewed", assessment.rationale

    sign_in @rm2
    patch sign_off_dashboard_vendor_assessment_path(@vendor, assessment), params: { review_note: "ok" }
    assert assessment.reload.signed_off?
  end

  test "a risk names its supplier, from the form or from the vendor page, and shows on the vendor" do
    sign_in @rm
    get dashboard_vendor_path(@vendor)
    assert_select "a[href=?]", dashboard_new_risk_path(vendor_id: @vendor.id)
    get dashboard_new_risk_path(vendor_id: @vendor.id)
    assert_select "select[name='risk[vendor_id]'] option[selected][value=?]", @vendor.id

    post "/dashboard/risk_management", params: { risk: { title: "Host outage", cause: "c", event: "e", impact_statement: "i",
      likelihood: 3, impact: 4, status: "identified", vendor_id: @vendor.id } }
    risk = Risk.find_by(title: "Host outage")
    assert_equal @vendor, risk.riskable
    get dashboard_vendor_path(@vendor)
    assert_select "a[href=?]", dashboard_risk_management_path(risk)
  end
end
