require "test_helper"

# Review 03, Q12: a vendor's rating is traceable to a signed-off assessment or
# an explicit override, and approval to use the supplier is its own state.
class Dashboard::VendorAssessmentsTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!
    @company = Company.create!(name: "Vend #{SecureRandom.hex(4)}", license_seats: 10, credits: 50, is_active: true)
    @admin = user("vend-admin", CompanyUser::ROLES[:company_admin])
    @rm = user("vend-rm", CompanyUser::ROLES[:company_risk_manager])
    @vendor = Vendor.create!(company: @company, name: "ACME Hosting", created_by: @admin)
  end

  def scores(n) = VendorAssessment::CRITERIA.index_with { n }

  test "a rating set by hand needs a reason" do
    sign_in @admin
    patch dashboard_vendor_path(@vendor), params: { vendor: { risk_level: "low" } }
    assert_equal "unassessed", @vendor.reload.risk_level

    patch dashboard_vendor_path(@vendor), params: { vendor: { risk_level: "low", rating_override_reason: "Legacy supplier, contract ends next month" } }
    @vendor.reload
    assert_equal "low", @vendor.risk_level
    assert_equal "manual", @vendor.rating_source
  end

  test "an assessment is scored, rated, signed off by a second person, and then sets the rating" do
    sign_in @admin
    post dashboard_vendor_assessments_path(@vendor), params: {
      vendor_assessment: { assessed_on: "2026-09-01", rationale: "SOC 2 report reviewed", next_review_on: "2027-03-01", scores: scores(4) }
    }
    assessment = @vendor.assessments.sole
    assert_equal "high", assessment.rating
    assert_equal 1, assessment.version
    refute assessment.signed_off?
    assert_equal "unassessed", @vendor.reload.risk_level, "a draft assessment changes nothing"

    patch sign_off_dashboard_vendor_assessment_path(@vendor, assessment)
    refute assessment.reload.signed_off?, "the assessor cannot sign off their own work"

    sign_out @admin
    sign_in @rm
    patch sign_off_dashboard_vendor_assessment_path(@vendor, assessment), params: { review_note: "Agreed" }
    assessment.reload
    assert assessment.signed_off?
    assert_equal @rm, assessment.reviewed_by
    @vendor.reload
    assert_equal "high", @vendor.risk_level
    assert_equal "assessed", @vendor.rating_source
    assert_equal Date.new(2027, 3, 1), @vendor.next_review_on
  end

  test "a missing score is refused with a readable message and the other values kept" do
    sign_in @admin
    post dashboard_vendor_assessments_path(@vendor), params: {
      vendor_assessment: { assessed_on: "2026-09-01", rationale: "Partial", scores: scores(3).except("continuity") }
    }
    assert_equal 0, @vendor.assessments.count
    assert_includes flash[:alert], I18n.t("vendor_assessment.criteria.continuity")
    follow_redirect!
    assert_select "textarea[name='vendor_assessment[rationale]']", text: "Partial"
  end

  test "approval is a separate decision, recorded with who and why, and a low rating does not imply it" do
    sign_in @admin
    @vendor.update!(risk_level: "low", rating_override_reason: "x")
    assert_equal "not_approved", @vendor.reload.approval_status

    patch approval_dashboard_vendor_path(@vendor), params: { approval_status: "conditionally_approved", approval_note: "Until the SOC 2 gap closes" }
    @vendor.reload
    assert_equal "conditionally_approved", @vendor.approval_status
    assert_equal @admin, @vendor.approved_by
    assert @vendor.approved_at.present?

    get dashboard_vendors_path
    assert_select "body", text: /#{Regexp.escape(I18n.t('vendor_assessment.approval_statuses.conditionally_approved'))}/
  end

  test "the rating for an average is graded on the five-point scale" do
    assert_equal "low", VendorAssessment.rating_for(2.4)
    assert_equal "medium", VendorAssessment.rating_for(2.5)
    assert_equal "high", VendorAssessment.rating_for(3.5)
    assert_equal "critical", VendorAssessment.rating_for(4.5)
  end

  private

  def user(tag, role)
    u = User.create!(email: "#{tag}-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: tag, is_active: true)
    CompanyUser.create!(company: @company, user: u, role: role)
    u
  end
end
