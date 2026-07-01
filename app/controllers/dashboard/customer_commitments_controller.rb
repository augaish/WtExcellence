class Dashboard::CustomerCommitmentsController < Dashboard::BaseController
  before_action :authenticate_user!
  before_action :ensure_not_risk_manager_only
  before_action :ensure_can_manage_commitments
  before_action :set_commitment, only: [ :show, :edit, :update, :destroy ]

  def index
    @commitments = CustomerCommitment.active.where(company_id: current_company&.id).includes(:owner).order(due_date: :asc)
    @past_due_count = @commitments.select(&:past_due?).size
  end

  def show
  end

  def new
    @commitment = CustomerCommitment.new
  end

  def create
    @commitment = CustomerCommitment.new(commitment_params)
    @commitment.company = current_company
    @commitment.created_by = current_user

    if @commitment.save
      redirect_to dashboard_customer_commitment_path(@commitment), notice: "Commitment logged successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @commitment.update(commitment_params)
      redirect_to dashboard_customer_commitment_path(@commitment), notice: "Commitment updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @commitment.soft_delete!
    redirect_to dashboard_customer_commitments_path, notice: "Commitment deleted successfully."
  end

  private

  def set_commitment
    @commitment = CustomerCommitment.active.where(company_id: current_company&.id).find(params[:id])
  end

  def commitment_params
    params.require(:customer_commitment).permit(:title, :description, :customer_name, :due_date, :status, :owner_id)
  end

  def ensure_can_manage_commitments
    unless current_user&.can_manage_commitments?
      respond_to do |format|
        format.html { redirect_to dashboard_capa_management_path, alert: "You don't have permission to manage customer commitments.", status: :forbidden }
        format.json { render json: { success: false, error: "You don't have permission to manage customer commitments." }, status: :forbidden }
      end
    end
  end
end
