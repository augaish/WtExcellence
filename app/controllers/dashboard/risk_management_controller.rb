class Dashboard::RiskManagementController < Dashboard::BaseController
  before_action :authenticate_user!
  before_action :ensure_can_manage_risks
  before_action :set_risk, only: [ :show, :edit, :update, :destroy ]

  def index
    @risks = Risk.active.where(company_id: current_company&.id).includes(:owner, :riskable).order(inherent_score: :desc)
    @heatmap = @risks.group_by { |risk| [ risk.likelihood, risk.impact ] }
  end

  def show
  end

  def new
    @risk = Risk.new
  end

  def create
    @risk = Risk.new(risk_params)
    @risk.company = current_company
    @risk.created_by = current_user

    if @risk.save
      redirect_to dashboard_risk_management_path(@risk), notice: "Risk logged successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @risk.update(risk_params)
      redirect_to dashboard_risk_management_path(@risk), notice: "Risk updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @risk.soft_delete!
    redirect_to dashboard_risk_management_index_path, notice: "Risk deleted successfully."
  end

  private

  def set_risk
    @risk = Risk.active.where(company_id: current_company&.id).find(params[:id])
  end

  def risk_params
    params.require(:risk).permit(
      :title, :description, :category, :owner_id, :status,
      :likelihood, :impact, :residual_likelihood, :residual_impact,
      :riskable_type, :riskable_id
    )
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
