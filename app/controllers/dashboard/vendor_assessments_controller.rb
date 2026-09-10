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
      redirect_to dashboard_vendor_path(@vendor), notice: t("vendor_assessment.flash.created", rating: t("risk_level_#{assessment.rating}")), status: :see_other
    else
      retain_form_values(:vendor_assessment, assessment_params)
      redirect_to dashboard_vendor_path(@vendor), alert: assessment.errors.full_messages.to_sentence, status: :see_other
    end
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
    redirect_to dashboard_vendor_path(@vendor), notice: t("vendor_assessment.flash.signed_off", rating: t("risk_level_#{assessment.rating}")), status: :see_other
  end

  private

  def set_vendor
    @vendor = Vendor.active.where(company_id: current_company&.id).find(params[:vendor_id])
  end

  def assessment_params
    permitted = params.require(:vendor_assessment).permit(:assessed_on, :rationale, :next_review_on, scores: VendorAssessment::CRITERIA)
    permitted[:scores] = (permitted[:scores] || {}).to_h.transform_values(&:to_i)
    permitted
  end

  def link_evidence(assessment)
    Array(params[:upload_ids]).reject(&:blank?).each do |upload_id|
      upload = current_company.uploads.find_by(id: upload_id) or next
      assessment.evidence_attachments.create!(upload: upload, attached_by: current_user.id)
    end
  end
end
