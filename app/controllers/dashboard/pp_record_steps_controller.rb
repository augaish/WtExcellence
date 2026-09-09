# Procedure steps, written inside the Documenter at Initial Draft Preparation.
class Dashboard::PpRecordStepsController < Dashboard::DocumenterContentController
  before_action :set_step, only: [ :update, :destroy ]

  def create
    step = @record.steps.new(step_params)
    step.position = @record.steps.maximum(:position).to_i + 1 if step_params[:position].blank?
    if step.save
      back(notice: t("documenter.flash.step_saved"))
    else
      retain_form_values(:pp_process_step, step_params)
      back(alert: step.errors.full_messages.to_sentence)
    end
  end

  def update
    if @step.update(step_params)
      back(notice: t("documenter.flash.step_saved"))
    else
      back(alert: @step.errors.full_messages.to_sentence)
    end
  end

  def destroy
    @step.destroy
    back(notice: t("documenter.flash.step_deleted"))
  end

  private

  def set_step
    @step = @record.steps.find_by(id: params[:id])
    back(alert: t("process_steps.flash.not_found")) if @step.nil?
  end

  def step_params
    params.require(:pp_process_step).permit(
      :position, :activity, :description, :responsible_title,
      :responsible_org_unit_id, :duration_value, :duration_unit, :system_used
    )
  end
end
