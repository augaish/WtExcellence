class Dashboard::PpProcessStepsController < Dashboard::PpProcessDetailController
  before_action :set_step, only: [ :update, :destroy ]

  def create
    step = @process.steps.new(step_params)
    # The column defaults to 1, so the step's own value is never blank; number
    # it from the end of the list unless a position was actually submitted.
    step.position = @process.steps.maximum(:position).to_i + 1 if step_params[:position].blank?

    if step.save
      back_to_process(notice: t("process_steps.flash.created"))
    else
      back_to_process(alert: step.errors.full_messages.to_sentence)
    end
  end

  def update
    if @step.update(step_params)
      back_to_process(notice: t("process_steps.flash.updated"))
    else
      back_to_process(alert: @step.errors.full_messages.to_sentence)
    end
  end

  def destroy
    @step.destroy
    back_to_process(notice: t("process_steps.flash.deleted"))
  end

  private

  def set_step
    @step = @process.steps.find_by(id: params[:id])
    back_to_process(alert: t("process_steps.flash.not_found")) if @step.nil?
  end

  def step_params
    params.require(:pp_process_step).permit(
      :position, :activity, :description, :responsible_title,
      :responsible_org_unit_id, :duration_value, :duration_unit, :system_used
    )
  end
end
