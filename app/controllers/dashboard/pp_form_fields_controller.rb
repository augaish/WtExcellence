# The fields of a form record, edited on the record page by whoever may
# manage records, while the record is still editable.
class Dashboard::PpFormFieldsController < Dashboard::BaseController
  requires_module :pp
  before_action :authenticate_user!
  before_action :set_record
  before_action :ensure_can_edit

  def create
    field = @record.form_fields.new(field_params)
    save_and_back(field, "form_fields.flash.saved")
  end

  def update
    field = @record.form_fields.find_by(id: params[:id])
    return back(alert: t("pp_records.flash.not_found")) if field.nil?

    field.assign_attributes(field_params)
    save_and_back(field, "form_fields.flash.saved")
  end

  def destroy
    @record.form_fields.find_by(id: params[:id])&.destroy
    back(notice: t("form_fields.flash.deleted"))
  end

  # Drag order from the page: ids as they now sit.
  def reorder
    ids = Array(params[:ids]).reject(&:blank?)
    @record.form_fields.where(id: ids).each { |f| f.update_columns(position: ids.index(f.id) + 1) }
    head :no_content
  end

  private

  def set_record
    @record = current_company&.pp_records&.find_by(id: params[:pp_record_id])
    return if @record&.form?

    redirect_to dashboard_pp_records_path, alert: t("pp_records.flash.not_found"), status: :see_other
  end

  def ensure_can_edit
    allowed = current_user&.platform_admin? || current_user&.company_user&.has_admin_privileges?
    return if allowed && @record.editable?

    back(alert: t("form_fields.flash.not_editable"))
  end

  def save_and_back(field, key)
    if field.save
      back(notice: t(key))
    else
      back(alert: field.errors.full_messages.to_sentence)
    end
  end

  def back(notice: nil, alert: nil)
    redirect_to dashboard_pp_record_path(@record, anchor: "form-fields"), notice: notice, alert: alert, status: :see_other
  end

  def field_params
    params.require(:pp_form_field).permit(:label_en, :label_ar, :field_type, :required, :options, :columns, :hint, :position)
  end
end
