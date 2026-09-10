# Measured periods of a service level, and the review that makes a
# measurement count towards attainment.
class Dashboard::SlaMeasurementsController < Dashboard::BaseController
  requires_module :pp
  before_action :authenticate_user!
  before_action :ensure_can_manage
  before_action :set_level

  def create
    measurement = @level.measurements.new(measurement_params)
    measurement.recorded_by = current_user
    if measurement.save
      back(notice: t("sla.flash.measured", state: measurement.met? ? t("sla.met") : t("sla.breached")))
    else
      retain_form_values(:sla_measurement, measurement_params)
      back(alert: measurement.errors.full_messages.to_sentence)
    end
  end

  # Four eyes: the person who recorded a number does not review it.
  def review
    measurement = @level.measurements.find_by(id: params[:id])
    return back(alert: t("sla.flash.not_found")) if measurement.nil?
    return back(alert: t("sla.flash.own_measurement")) if measurement.recorded_by_id == current_user.id

    measurement.review!(by: current_user)
    back(notice: t("sla.flash.reviewed"))
  end

  private

  def company
    @company ||= current_company
  end

  def set_level
    @record = company&.pp_records&.find_by(id: params[:pp_record_id])
    @level = @record&.service_levels&.find_by(id: params[:service_level_id])
    return if @level

    redirect_to dashboard_pp_records_path, alert: t("sla.flash.not_found"), status: :see_other
  end

  def ensure_can_manage
    return if RecordAuthoring.allowed?(current_user, company)

    redirect_to dashboard_pp_records_path, alert: t("pp_records.flash.no_permission"), status: :see_other
  end

  def measurement_params
    params.require(:sla_measurement).permit(:period_start, :period_end, :actual_value, :source_note)
  end

  def back(notice: nil, alert: nil)
    redirect_to dashboard_pp_record_path(@record), notice: notice, alert: alert, status: :see_other
  end
end
