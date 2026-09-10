class Dashboard::VendorsController < Dashboard::BaseController
  before_action :authenticate_user!
  requires_module :vendors
  before_action :ensure_can_view_governance, only: [ :index, :show ]
  before_action :ensure_can_manage_vendors, except: [ :index, :show ]
  before_action :set_vendor, only: [ :show, :edit, :update, :destroy, :create_capa, :approval ]

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
    @assessments = @vendor.assessments.includes(:assessed_by, :reviewed_by, uploads: :folder).to_a
    @assessment = VendorAssessment.new(vendor: @vendor, assessed_on: Date.current)
    @available_uploads = current_company.uploads.includes(:folder).order(created_at: :desc).limit(100)
  end

  # Approval to use the supplier: a decision of its own, by an admin or a
  # Governance Manager, recorded with who took it and why.
  def approval
    status = params[:approval_status].to_s
    unless Vendor::APPROVAL_STATUSES.include?(status)
      return redirect_to dashboard_vendor_path(@vendor), alert: t("vendor_assessment.flash.unknown_approval"), status: :see_other
    end

    @vendor.record_approval!(status, by: current_user, note: params[:approval_note])
    redirect_to dashboard_vendor_path(@vendor), notice: t("vendor_assessment.flash.approval_recorded"), status: :see_other
  end

  def new
    @vendor = Vendor.new
  end

  def create
    @vendor = Vendor.new(vendor_params)
    @vendor.company = current_company
    @vendor.created_by = current_user
    @vendor.rating_source = "manual"
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
    # A rating typed here is a manual one; the assessment path sets its own.
    @vendor.rating_source = "manual" if @vendor.risk_level_changed?
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
    params.require(:vendor).permit(:name, :category, :risk_level, :rating_override_reason, :contact_email, :owner_id, :notes,
      :criticality, :service_description, :contract_end_on, :next_review_on)
  end
end
