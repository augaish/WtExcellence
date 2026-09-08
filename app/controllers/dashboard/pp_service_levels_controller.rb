# The measurable commitments of a service level agreement, managed on the
# agreement itself.
class Dashboard::PpServiceLevelsController < Dashboard::BaseController
  requires_module :pp
  before_action :authenticate_user!
  before_action :ensure_can_manage
  before_action :set_record

  def create
    level = @record.service_levels.new(service_level_params)
    level.sort_order = @record.service_levels.maximum(:sort_order).to_i + 1

    if level.save
      back_to_record(notice: t("sla.flash.created"))
    else
      back_to_record(alert: level.errors.full_messages.to_sentence)
    end
  end

  def update
    level = @record.service_levels.find_by(id: params[:id])
    return back_to_record(alert: t("sla.flash.not_found")) if level.nil?

    if level.update(service_level_params)
      back_to_record(notice: t("sla.flash.updated"))
    else
      back_to_record(alert: level.errors.full_messages.to_sentence)
    end
  end

  def destroy
    @record.service_levels.find_by(id: params[:id])&.destroy
    back_to_record(notice: t("sla.flash.deleted"))
  end

  private

  def company
    @company ||= current_company
  end

  def set_record
    @record = company&.pp_records&.find_by(id: params[:pp_record_id])
    return if @record

    redirect_to dashboard_pp_records_path, alert: t("pp_records.flash.not_found"), status: :see_other
  end

  def ensure_can_manage
    membership = current_user&.company_user
    return if current_user&.platform_admin?
    return if membership.present? && (membership.has_admin_privileges? || membership.company_quality_manager?)

    redirect_to dashboard_pp_records_path, alert: t("pp_records.flash.no_permission"), status: :see_other
  end

  def back_to_record(notice: nil, alert: nil)
    redirect_to dashboard_pp_record_path(@record), notice: notice, alert: alert, status: :see_other
  end

  def service_level_params
    params.require(:pp_service_level).permit(:service_name, :metric, :target_value, :target_unit,
      :measurement_method, :coverage, :escalation_path, :remedy)
  end
end
