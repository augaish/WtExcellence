class Dashboard::RiskWorkspacesController < Dashboard::BaseController
  before_action :authenticate_user!
  before_action :ensure_can_manage_risks
  before_action :set_risk_workspace, only: [ :show, :edit, :update, :destroy ]

  def index
    @risk_workspaces = RiskWorkspace.active.where(company_id: current_company&.id).order(:name)
  end

  def show
    @risks = @risk_workspace.risks.active.includes(:owner, :riskable).order(inherent_score: :desc)
  end

  def new
    @risk_workspace = RiskWorkspace.new
  end

  def create
    @risk_workspace = RiskWorkspace.new(risk_workspace_params)
    @risk_workspace.company = current_company

    if @risk_workspace.save
      redirect_to dashboard_risk_workspace_path(@risk_workspace), notice: "Risk workspace created successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @risk_workspace.update(risk_workspace_params)
      redirect_to dashboard_risk_workspace_path(@risk_workspace), notice: "Risk workspace updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @risk_workspace.soft_delete!
    redirect_to dashboard_risk_workspaces_path, notice: "Risk workspace deleted successfully."
  end

  private

  def set_risk_workspace
    @risk_workspace = RiskWorkspace.active.where(company_id: current_company&.id).find(params[:id])
  end

  def risk_workspace_params
    params.require(:risk_workspace).permit(:name, :framework, :description, :department_scope)
  end

  def ensure_can_manage_risks
    unless current_user&.can_manage_risks?
      respond_to do |format|
        format.html { redirect_to dashboard_capa_management_path, alert: "You don't have permission to manage risks.", status: :forbidden }
        format.json { render json: { success: false, error: "You don't have permission to manage risks." }, status: :forbidden }
      end
    end
  end
end
