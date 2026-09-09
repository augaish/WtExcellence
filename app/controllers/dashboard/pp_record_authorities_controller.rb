# Operational authorities: one decision inside a procedure, written beside the
# step that makes it, in the Documenter.
class Dashboard::PpRecordAuthoritiesController < Dashboard::DocumenterContentController
  def create
    authority = @record.operational_authorities.new(authority_params)
    authority.sort_order = @record.operational_authorities.maximum(:sort_order).to_i + 1
    authority.pp_process_step = @record.steps.find_by(id: params[:step_id]) if params[:step_id].present?

    if authority.save
      back(notice: t("process_authorities.flash.created"))
    else
      back(alert: authority.errors.full_messages.to_sentence)
    end
  end

  def destroy
    @record.operational_authorities.find_by(id: params[:id])&.destroy
    back(notice: t("process_authorities.flash.deleted"))
  end

  private

  def authority_params
    params.require(:pp_process_authority).permit(:item, :decision, :authority_id)
  end
end
