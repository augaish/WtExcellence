class Dashboard::AiInstructionsController < Dashboard::BaseController
  before_action :authenticate_user!
  requires_module :ai_instructions
  before_action :ensure_not_risk_manager_only
  before_action :ensure_can_manage_ai_instructions
  before_action :set_ai_instruction, only: [ :edit, :update, :destroy, :toggle ]

  def index
    @ai_instructions = AiInstruction.where(company_id: current_company&.id, deleted_at: nil).order(:created_at)
  end

  def new
    @ai_instruction = AiInstruction.new(active: true)
  end

  def create
    @ai_instruction = AiInstruction.new(ai_instruction_params)
    @ai_instruction.company = current_company
    @ai_instruction.created_by = current_user

    if @ai_instruction.save
      log_change("CREATE_AI_INSTRUCTION")
      redirect_to dashboard_ai_instructions_path, notice: t("ai_instruction_created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @ai_instruction.update(ai_instruction_params)
      log_change("UPDATE_AI_INSTRUCTION")
      redirect_to dashboard_ai_instructions_path, notice: t("ai_instruction_updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def toggle
    @ai_instruction.update!(active: !@ai_instruction.active)
    log_change("TOGGLE_AI_INSTRUCTION")
    redirect_to dashboard_ai_instructions_path, notice: t("ai_instruction_updated")
  end

  def destroy
    @ai_instruction.soft_delete!
    log_change("DELETE_AI_INSTRUCTION")
    redirect_to dashboard_ai_instructions_path, notice: t("ai_instruction_deleted")
  end

  private

  def set_ai_instruction
    @ai_instruction = AiInstruction.where(company_id: current_company&.id, deleted_at: nil).find(params[:id])
  end

  def ai_instruction_params
    params.require(:ai_instruction).permit(:title, :content_en, :content_ar, :active)
  end

  def ensure_can_manage_ai_instructions
    return if current_user&.can_manage_ai_instructions?

    respond_to do |format|
      format.html { redirect_to dashboard_capa_management_path, alert: t("grc.no_permission_ai_instructions"), status: :see_other }
      format.json { render json: { success: false, error: t("grc.no_permission_ai_instructions") }, status: :forbidden }
    end
  end

  def log_change(action)
    AuditLogService.log_action(
      actor_user: current_user,
      company: current_company,
      action: action,
      entity_type: "ai_instruction",
      entity_id: @ai_instruction.id,
      payload: { title: @ai_instruction.title, active: @ai_instruction.active }
    )
  end
end
