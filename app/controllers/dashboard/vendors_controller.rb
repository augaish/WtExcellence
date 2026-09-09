class Dashboard::VendorsController < Dashboard::BaseController
  before_action :authenticate_user!
  requires_module :vendors
  before_action :ensure_can_view_governance, only: [ :index, :show ]
  before_action :ensure_can_manage_vendors, except: [ :index, :show ]
  before_action :set_vendor, only: [ :show, :edit, :update, :destroy, :create_capa ]

  def index
    # Order by real severity (critical first), not alphabetically — the string
    # enum would otherwise sort "critical" last and "unassessed" first.
    severity_order = Arel.sql(
      "CASE risk_level " \
      "WHEN 'critical' THEN 0 WHEN 'high' THEN 1 WHEN 'medium' THEN 2 " \
      "WHEN 'low' THEN 3 ELSE 4 END"
    )
    all_vendors = Vendor.active.where(company_id: current_company&.id)
    @filter = GovernanceRegisterFilter.new(all_vendors, params: params,
      company_user: current_user&.company_user, company: current_company)
    @total_count = all_vendors.count
    @vendors = @filter.results.includes(:owner).order(severity_order, name: :asc)
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
    sanitize_company_owner!(@vendor)

    if @vendor.save
      redirect_to dashboard_vendor_path(@vendor), notice: t("vendor_added")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    @vendor.assign_attributes(vendor_params)
    sanitize_company_owner!(@vendor)

    if @vendor.save
      redirect_to dashboard_vendor_path(@vendor), notice: t("vendor_updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @vendor.soft_delete!
    redirect_to dashboard_vendors_path, notice: t("vendor_deleted")
  end

  # Raise a linked CAPA from this vendor and hand off to the CAPA workflow.
  def create_capa
    capa = GovernanceCapaService.create_from(origin: @vendor, company: current_company, user: current_user)
    redirect_to dashboard_capa_management_show_path(capa), notice: t("capa_raised_from_governance")
  rescue GovernanceCapaService::UnsupportedOriginError, ActiveRecord::RecordInvalid
    redirect_to dashboard_vendor_path(@vendor), alert: t("capa_raise_failed")
  end

  private

  def set_vendor
    @vendor = Vendor.active.where(company_id: current_company&.id).find(params[:id])
  end

  def vendor_params
    params.require(:vendor).permit(:name, :category, :risk_level, :contact_email, :owner_id, :notes)
  end
end
