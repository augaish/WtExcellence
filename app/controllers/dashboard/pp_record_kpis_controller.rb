# The KPI rows of a procedure, edited on the record page while it is editable.
class Dashboard::PpRecordKpisController < Dashboard::BaseController
  requires_module :pp
  before_action :authenticate_user!
  before_action :set_record
  before_action :ensure_can_edit

  def create
    save_and_back(@record.kpi_rows.new(kpi_params))
  end

  def update
    kpi = @record.kpi_rows.find_by(id: params[:id])
    return back(alert: t("pp_records.flash.not_found")) if kpi.nil?

    kpi.assign_attributes(kpi_params)
    save_and_back(kpi)
  end

  def destroy
    @record.kpi_rows.find_by(id: params[:id])&.destroy
    back(notice: t("kpis.flash.deleted"))
  end

  def reorder
    ids = Array(params[:ids]).reject(&:blank?)
    @record.kpi_rows.where(id: ids).each { |k| k.update_columns(sort_order: ids.index(k.id) + 1) }
    head :no_content
  end

  private

  def set_record
    @record = current_company&.pp_records&.find_by(id: params[:pp_record_id])
    return if @record&.procedure?

    redirect_to dashboard_pp_records_path, alert: t("pp_records.flash.not_found"), status: :see_other
  end

  def ensure_can_edit
    allowed = current_user&.platform_admin? || current_user&.company_user&.has_admin_privileges?
    return if allowed && @record.editable?

    back(alert: t("kpis.flash.not_editable"))
  end

  def save_and_back(kpi)
    if kpi.save
      back(notice: t("kpis.flash.saved"))
    else
      back(alert: kpi.errors.full_messages.to_sentence)
    end
  end

  def back(notice: nil, alert: nil)
    redirect_to dashboard_pp_record_path(@record, anchor: "kpis"), notice: notice, alert: alert, status: :see_other
  end

  def kpi_params
    params.require(:pp_record_kpi).permit(:name_en, :name_ar, :target, :unit, :measurement_method, :frequency)
  end
end
