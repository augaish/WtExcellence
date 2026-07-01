class Dashboard::VendorsController < Dashboard::BaseController
  before_action :authenticate_user!
  before_action :ensure_not_risk_manager_only
  before_action :ensure_can_manage_vendors
  before_action :set_vendor, only: [ :show, :edit, :update, :destroy ]

  def index
    @vendors = Vendor.active.where(company_id: current_company&.id).includes(:owner).order(risk_level: :desc, name: :asc)
  end

  def show
  end

  def new
    @vendor = Vendor.new
  end

  def create
    @vendor = Vendor.new(vendor_params)
    @vendor.company = current_company
    @vendor.created_by = current_user

    if @vendor.save
      redirect_to dashboard_vendor_path(@vendor), notice: "Vendor added successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @vendor.update(vendor_params)
      redirect_to dashboard_vendor_path(@vendor), notice: "Vendor updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @vendor.soft_delete!
    redirect_to dashboard_vendors_path, notice: "Vendor deleted successfully."
  end

  private

  def set_vendor
    @vendor = Vendor.active.where(company_id: current_company&.id).find(params[:id])
  end

  def vendor_params
    params.require(:vendor).permit(:name, :category, :risk_level, :contact_email, :owner_id, :notes)
  end

  def ensure_can_manage_vendors
    unless current_user&.can_manage_vendors?
      respond_to do |format|
        format.html { redirect_to dashboard_capa_management_path, alert: "You don't have permission to manage vendors.", status: :forbidden }
        format.json { render json: { success: false, error: "You don't have permission to manage vendors." }, status: :forbidden }
      end
    end
  end
end
