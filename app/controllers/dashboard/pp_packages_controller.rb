class Dashboard::PpPackagesController < Dashboard::BaseController
  requires_module :pp
  before_action :authenticate_user!
  before_action :ensure_company_present
  before_action :ensure_can_manage, only: [
    :new, :create, :edit, :update, :destroy, :assign_record, :remove_record
  ]
  before_action :set_package, only: [ :show, :edit, :update, :destroy, :assign_record, :remove_record ]

  helper_method :can_manage_pp_records?

  def index
    @packages = company.pp_packages.includes(:pp_records).ordered.to_a
  end

  # A package is composed here: one sub-tab per record type, each a checklist of
  # that type's records.
  def show
    @record_type = params[:record_type].presence || PpRecord::TYPES.first
    @record_type = PpRecord::TYPES.first unless PpRecord::TYPES.include?(@record_type)

    @records = company.pp_records.active.of_type(@record_type)
      .includes(:package, :owner_org_unit).ordered.to_a
    @members = @package.pp_records.includes(:owner_org_unit).ordered.to_a
    @counts_by_type = company.pp_records.active.group(:record_type).count
  end

  def new
    @package = company.pp_packages.new
    render :new
  end

  def edit; end

  def create
    @package = company.pp_packages.new(package_params)
    @package.company = company

    if @package.save
      log_action("CREATE_PP_PACKAGE")
      redirect_to dashboard_pp_package_path(@package), notice: t("pp_records.packages.flash.created"), status: :see_other
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @package.update(package_params)
      log_action("UPDATE_PP_PACKAGE")
      redirect_to dashboard_pp_package_path(@package), notice: t("pp_records.packages.flash.updated"), status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    # Records survive; they simply become unpackaged (dependent: :nullify).
    @package.destroy
    log_action("DELETE_PP_PACKAGE")
    redirect_to dashboard_pp_packages_path, notice: t("pp_records.packages.flash.deleted"), status: :see_other
  end

  # Tick a record into this package. If it already belongs to a DIFFERENT
  # package we refuse and report the conflict; moving it requires an explicit
  # re-assign, so a package can never quietly steal a committed record.
  def assign_record
    record = company.pp_records.find_by(id: params[:record_id])
    unless record
      return redirect_back_to_package(alert: t("pp_records.flash.not_found"))
    end

    reassign = ActiveModel::Type::Boolean.new.cast(params[:reassign])

    begin
      record.assign_to_package!(@package, reassign: reassign)
      log_action(reassign ? "REASSIGN_PP_RECORD_PACKAGE" : "ASSIGN_PP_RECORD_PACKAGE")
      redirect_back_to_package(notice: t("pp_records.packages.flash.record_added", title: record.display_title))
    rescue PpRecord::PackageConflict => e
      redirect_back_to_package(
        alert: t("pp_records.packages.flash.conflict",
                 title: record.display_title, package: e.current_package&.name)
      )
    end
  end

  def remove_record
    record = @package.pp_records.find_by(id: params[:record_id])
    unless record
      return redirect_back_to_package(alert: t("pp_records.flash.not_found"))
    end

    record.remove_from_package!
    log_action("REMOVE_PP_RECORD_PACKAGE")
    redirect_back_to_package(notice: t("pp_records.packages.flash.record_removed", title: record.display_title))
  end

  private

  def company
    @company ||= current_company
  end

  def ensure_company_present
    return if company

    redirect_to dashboard_overview_path, alert: t("pp_records.flash.no_company"), status: :see_other
  end

  def can_manage_pp_records?
    return true if current_user&.platform_admin?

    cu = current_user&.company_user
    cu.present? && (cu.has_admin_privileges? || cu.company_quality_manager?)
  end

  def ensure_can_manage
    return if can_manage_pp_records?

    redirect_to dashboard_pp_packages_path, alert: t("pp_records.flash.no_permission"), status: :see_other
  end

  def set_package
    @package = company.pp_packages.find_by(id: params[:id])
    return if @package

    redirect_to dashboard_pp_packages_path, alert: t("pp_records.packages.flash.not_found"), status: :see_other
  end

  def redirect_back_to_package(**flash_opts)
    redirect_to dashboard_pp_package_path(@package, record_type: params[:record_type]),
      status: :see_other, **flash_opts
  end

  def package_params
    params.require(:pp_package).permit(:name, :start_date, :end_date, :notes)
  end

  def log_action(action)
    AuditLogService.log_action(
      actor_user: current_user, company: company, action: action,
      entity_type: "pp_package", entity_id: @package&.id,
      payload: { name: @package&.name }
    )
  end
end
