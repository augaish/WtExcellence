# A vendor's assessments: written by anyone who may manage vendors, signed
# off by a second person so the rating is never one opinion.
class Dashboard::VendorAssessmentsController < Dashboard::BaseController
  before_action :authenticate_user!
  requires_module :vendors
  before_action :ensure_can_manage_vendors
  before_action :set_vendor

  def create
    assessment = @vendor.assessments.new(assessment_params)
    assessment.company = current_company
    assessment.assessed_by = current_user

    if assessment.save
      link_evidence(assessment)
      notify_reviewers(assessment)
      redirect_to dashboard_vendor_path(@vendor), notice: t("vendor_assessment.flash.created", rating: t("risk_level_#{assessment.rating}")), status: :see_other
    else
      retain_form_values(:vendor_assessment, assessment_params)
      redirect_to dashboard_vendor_path(@vendor), alert: assessment.errors.full_messages.to_sentence, status: :see_other
    end
  end

  # The assessor corrects a returned (or not yet signed) assessment and
  # resubmits it; the reviewers are told again.
  def update
    assessment = @vendor.assessments.find_by(id: params[:id])
    return redirect_to dashboard_vendor_path(@vendor), alert: t("vendor_assessment.flash.not_found"), status: :see_other if assessment.nil?
    if assessment.signed_off? || assessment.assessed_by_id != current_user.id
      return redirect_to dashboard_vendor_path(@vendor), alert: t("vendor_assessment.flash.not_editable"), status: :see_other
    end

    assessment.assign_attributes(assessment_params.merge(returned_at: nil))
    if assessment.save
      link_evidence(assessment)
      notify_reviewers(assessment)
      redirect_to dashboard_vendor_path(@vendor), notice: t("vendor_assessment.flash.resubmitted"), status: :see_other
    else
      redirect_to dashboard_vendor_path(@vendor), alert: assessment.errors.full_messages.to_sentence, status: :see_other
    end
  end

  # The reviewer sends it back with what needs changing.
  def return_for_rework
    assessment = @vendor.assessments.find_by(id: params[:id])
    return redirect_to dashboard_vendor_path(@vendor), alert: t("vendor_assessment.flash.not_found"), status: :see_other if assessment.nil?
    return redirect_to dashboard_vendor_path(@vendor), alert: t("vendor_assessment.flash.already_signed"), status: :see_other if assessment.signed_off?
    if assessment.assessed_by_id == current_user.id
      return redirect_to dashboard_vendor_path(@vendor), alert: t("vendor_assessment.flash.own_work"), status: :see_other
    end
    reason = params[:return_reason].to_s.strip
    return redirect_to dashboard_vendor_path(@vendor), alert: t("vendor_assessment.flash.reason_required"), status: :see_other if reason.blank?

    assessment.return_for_rework!(by: current_user, reason: reason)
    Notify.person(assessment.assessed_by, kind: "vendor_assessment_returned", source: @vendor,
      link_path: dashboard_vendor_path(@vendor, anchor: "assessments"), actor: current_user, vendor: @vendor.name, reason: reason)
    redirect_to dashboard_vendor_path(@vendor), notice: t("vendor_assessment.flash.returned"), status: :see_other
  end

  # Four eyes: the assessor may not sign off their own work.
  def sign_off
    assessment = @vendor.assessments.find_by(id: params[:id])
    return redirect_to dashboard_vendor_path(@vendor), alert: t("vendor_assessment.flash.not_found"), status: :see_other if assessment.nil?
    return redirect_to dashboard_vendor_path(@vendor), alert: t("vendor_assessment.flash.already_signed"), status: :see_other if assessment.signed_off?
    if assessment.assessed_by_id == current_user.id
      return redirect_to dashboard_vendor_path(@vendor), alert: t("vendor_assessment.flash.own_work"), status: :see_other
    end

    assessment.sign_off!(by: current_user, note: params[:review_note])
    Notify.person(assessment.assessed_by, kind: "vendor_assessment_signed_off", source: @vendor,
      link_path: dashboard_vendor_path(@vendor), actor: current_user, vendor: @vendor.name, rating: t("risk_level_#{assessment.rating}"))
    redirect_to dashboard_vendor_path(@vendor), notice: t("vendor_assessment.flash.signed_off", rating: t("risk_level_#{assessment.rating}")), status: :see_other
  end

  private

  def set_vendor
    @vendor = Vendor.active.where(company_id: current_company&.id).find(params[:vendor_id])
  end

  def assessment_params
    permitted = params.require(:vendor_assessment).permit(:assessed_on, :rationale, :next_review_on, scores: VendorAssessment::CRITERIA)
    permitted[:scores] ||= {}
    permitted[:scores] = (permitted[:scores] || {}).to_h.transform_values(&:to_i)
    permitted
  end

  def link_evidence(assessment)
    EvidenceIntake.attach(assessment, company: current_company, user: current_user,
      upload_ids: params[:upload_ids], files: params[:files], folder_name: t("vendor_management"))
  end

  # Whoever may sign it off: admins, risk managers and Governance Managers,
  # never the assessor.
  def notify_reviewers(assessment)
    reviewers = current_company.company_users.includes(:user).select(&:can_manage_governance?).map(&:user)
    Notify.people(reviewers, kind: "vendor_assessment_submitted", source: @vendor,
      link_path: dashboard_vendor_path(@vendor, anchor: "assessments"), actor: current_user,
      vendor: @vendor.name, rating: t("risk_level_#{assessment.rating}"))
  end
end
