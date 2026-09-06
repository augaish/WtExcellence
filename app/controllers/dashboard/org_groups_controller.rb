class Dashboard::OrgGroupsController < Dashboard::BaseController
  requires_module :org_structure
  before_action :authenticate_user!
  before_action :ensure_can_manage
  before_action :set_group, only: [ :update, :destroy ]

  def create
    group = current_company.org_groups.new(group_params)
    group.sort_order = current_company.org_groups.count if group.sort_order.blank?

    if group.save
      redirect_to settings_dashboard_org_units_path, notice: t("org_structure.flash.group_created"), status: :see_other
    else
      redirect_to settings_dashboard_org_units_path, alert: group.errors.full_messages.to_sentence, status: :see_other
    end
  end

  def update
    if @group.update(group_params)
      redirect_to settings_dashboard_org_units_path, notice: t("org_structure.flash.group_updated"), status: :see_other
    else
      redirect_to settings_dashboard_org_units_path, alert: @group.errors.full_messages.to_sentence, status: :see_other
    end
  end

  def destroy
    @group.destroy
    redirect_to settings_dashboard_org_units_path, notice: t("org_structure.flash.group_deleted"), status: :see_other
  end

  private

  def set_group
    @group = current_company.org_groups.find_by(id: params[:id])
    return if @group

    redirect_to settings_dashboard_org_units_path, alert: t("org_structure.flash.not_found"), status: :see_other
  end

  def ensure_can_manage
    return if current_user&.platform_admin?

    cu = current_user&.company_user
    return if cu.present? && (cu.has_admin_privileges? || cu.company_quality_manager?)

    redirect_to dashboard_org_units_path, alert: t("org_structure.flash.no_permission"), status: :see_other
  end

  def group_params
    params.require(:org_group).permit(:name_en, :name_ar, :color, :sort_order)
  end
end
