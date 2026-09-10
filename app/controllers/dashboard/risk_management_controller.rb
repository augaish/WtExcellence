class Dashboard::RiskManagementController < Dashboard::BaseController
  before_action :authenticate_user!
  requires_module :risk
  before_action :ensure_can_view_governance, only: [ :index, :show ]
  before_action :ensure_can_manage_risks, except: [ :index, :show ]
  before_action :set_risk, only: [ :show, :edit, :update, :destroy, :create_capa ]

  def index
    all_risks = Risk.active.where(company_id: current_company&.id)

    # Search and queues, shared with the other governance registers.
    @filter = GovernanceRegisterFilter.new(all_risks, params: params,
      company_user: current_user&.company_user, company: current_company)
    @total_count = all_risks.count
    @risks = @filter.results.includes(:owner, :riskable, :risk_workspace).order(inherent_score: :desc)

    # The matrix always describes the whole register, not the current search:
    # a heatmap of filtered results would invite the wrong conclusion.

    # The matrix counted every risk including closed ones while the summary
    # counted only open, so the two disagreed with no way to tell why. The
    # population is now chosen and stated.
    @matrix_population = params[:population] == "all" ? "all" : "open"
    matrix_source = all_risks.includes(:owner)
    matrix_risks = @matrix_population == "all" ? matrix_source.to_a : matrix_source.reject(&:closed?)
    @matrix_risk_count = matrix_risks.size
    @heatmap = matrix_risks.group_by { |risk| [ risk.likelihood, risk.impact ] }
    @risk_workspaces = RiskWorkspace.active.where(company_id: current_company&.id).order(:name)
    @risks_by_workspace = @risks.group_by(&:risk_workspace)
  end

  def show
  end

  # The appetite is a company-level threshold, set where the register that uses
  # it lives rather than buried in general settings.
  def update_appetite
    unless current_user&.can_manage_governance?
      return redirect_to dashboard_risk_management_index_path,
        alert: t("risk_no_permission"), status: :see_other
    end

    score = params.require(:company).permit(:risk_appetite_score)[:risk_appetite_score]
    current_company.update!(risk_appetite_score: score.presence)

    redirect_to dashboard_risk_management_index_path,
      notice: t("risk_methodology.appetite_saved"), status: :see_other
  end

  def new
    @risk = Risk.new
    load_form_collections
  end

  def create
    # A retry after an uncertain response lands on the record already made.
    token = params[:submission_token].presence
    if token && (existing = Risk.active.find_by(company_id: current_company&.id, submission_token: token))
      return redirect_to dashboard_risk_management_path(existing), status: :see_other
    end

    @risk = Risk.new(risk_params)
    @risk.company = current_company
    @risk.created_by = current_user
    @risk.submission_token = params[:submission_token].presence
    reject_cross_company_workspace(@risk)
    sanitize_company_owner!(@risk)

    if @risk.save
      redirect_to dashboard_risk_management_path(@risk), notice: t("risk_logged")
    else
      load_form_collections
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    load_form_collections
  end

  def update
    @risk.assign_attributes(risk_params)
    reject_cross_company_workspace(@risk)
    sanitize_company_owner!(@risk)

    if @risk.save
      redirect_to dashboard_risk_management_path(@risk), notice: t("risk_updated")
    else
      load_form_collections
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @risk.soft_delete!
    redirect_to dashboard_risk_management_index_path, notice: t("risk_deleted")
  end

  # Raise a linked CAPA from this risk and hand off to the CAPA workflow.
  def create_capa
    capa = GovernanceCapaService.create_from(origin: @risk, company: current_company, user: current_user)
    redirect_to dashboard_capa_management_show_path(capa), notice: t("capa_raised_from_governance")
  rescue GovernanceCapaService::UnsupportedOriginError, ActiveRecord::RecordInvalid
    redirect_to dashboard_risk_management_path(@risk), alert: t("capa_raise_failed")
  end

  private

  # Every collection the form offers. Loaded for the failure paths too, so a
  # validation error cannot silently remove a choice the user already had.
  def load_form_collections
    @risk_workspaces = RiskWorkspace.active.where(company_id: current_company&.id).order(:name)
  end

  def set_risk
    @risk = Risk.active.where(company_id: current_company&.id).find(params[:id])
  end

  def risk_params
    params.require(:risk).permit(
      :title, :description, :category, :owner_id, :status,
      :likelihood, :impact, :residual_likelihood, :residual_impact,
      :target_likelihood, :target_impact,
      :risk_workspace_id, :closure_reason
    )
  end

  # Prevent assigning a risk to another company's workspace via mass assignment
  def reject_cross_company_workspace(risk)
    return if risk.risk_workspace_id.blank?

    valid = RiskWorkspace.active.where(company_id: current_company&.id).exists?(id: risk.risk_workspace_id)
    risk.risk_workspace_id = nil unless valid
  end
end
