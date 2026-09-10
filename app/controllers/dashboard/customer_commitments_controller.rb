class Dashboard::CustomerCommitmentsController < Dashboard::BaseController
  before_action :authenticate_user!
  requires_module :commitments
  before_action :ensure_can_view_governance, only: [ :index, :show ]
  before_action :ensure_can_manage_commitments, except: [ :index, :show ]
  before_action :set_commitment, only: [ :show, :edit, :update, :destroy, :create_capa ]

  def index
    all_commitments = CustomerCommitment.active.where(company_id: current_company&.id)
    @filter = GovernanceRegisterFilter.new(all_commitments, params: params,
      company_user: current_user&.company_user, company: current_company)
    @total_count = all_commitments.count
    @commitments = @filter.results.includes(:owner).order(due_date: :asc)

    # The overdue count describes the whole register, not the current filter.
    @past_due_count = all_commitments.to_a.select(&:past_due?).size
  end

  def show
  end

  def new
    @commitment = CustomerCommitment.new
  end

  def create
    # A retry after an uncertain response lands on the record already made.
    token = params[:submission_token].presence
    if token && (existing = CustomerCommitment.active.find_by(company_id: current_company&.id, submission_token: token))
      return redirect_to dashboard_customer_commitment_path(existing), status: :see_other
    end

    @commitment = CustomerCommitment.new(commitment_params)
    @commitment.company = current_company
    @commitment.created_by = current_user
    @commitment.submission_token = params[:submission_token].presence
    sanitize_company_owner!(@commitment)

    if @commitment.save
      redirect_to dashboard_customer_commitment_path(@commitment), notice: t("commitment_logged")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    @commitment.assign_attributes(commitment_params)
    sanitize_company_owner!(@commitment)

    if @commitment.save
      redirect_to dashboard_customer_commitment_path(@commitment), notice: t("commitment_updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @commitment.soft_delete!
    redirect_to dashboard_customer_commitments_path, notice: t("commitment_deleted")
  end

  # Raise a linked CAPA from this commitment and hand off to the CAPA workflow.
  def create_capa
    capa = GovernanceCapaService.create_from(origin: @commitment, company: current_company, user: current_user)
    redirect_to dashboard_capa_management_show_path(capa), notice: t("capa_raised_from_governance")
  rescue GovernanceCapaService::UnsupportedOriginError, ActiveRecord::RecordInvalid
    redirect_to dashboard_customer_commitment_path(@commitment), alert: t("capa_raise_failed")
  end

  private

  def set_commitment
    @commitment = CustomerCommitment.active.where(company_id: current_company&.id).find(params[:id])
  end

  def commitment_params
    params.require(:customer_commitment).permit(:title, :description, :customer_name, :due_date, :status, :owner_id, :fulfillment_note)
  end
end
