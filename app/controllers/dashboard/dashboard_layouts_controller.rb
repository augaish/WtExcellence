class Dashboard::DashboardLayoutsController < Dashboard::BaseController
  before_action :require_customize_access

  # PATCH — persist one slot's widget order + hidden list, and make it active.
  def update
    layout = DashboardLayout.resolve(scope: layout_scope, company_id: layout_company_id, slot: params[:slot])
    layout.name = params[:name].to_s.strip.presence || layout.name || default_slot_name(layout.slot)
    layout.config = {
      "order" => sanitize_keys(params[:order]),
      "hidden" => sanitize_keys(params[:hidden])
    }
    layout.company_id = layout_company_id unless layout_scope == "platform"
    layout.save!

    activate_slot(layout.slot)

    render json: { ok: true, slot: layout.slot, name: layout.name }
  rescue ActiveRecord::RecordInvalid => e
    render json: { ok: false, error: e.message }, status: :unprocessable_entity
  end

  # POST — switch the active slot without changing any stored config.
  def activate
    slot = params[:slot].to_i
    unless DashboardLayout::SLOTS.include?(slot)
      return render json: { ok: false, error: "invalid slot" }, status: :unprocessable_entity
    end

    activate_slot(slot)
    redirect_to dashboard_overview_path, status: :see_other
  end

  private

  # Only known widget keys are stored — prevents arbitrary values in config.
  def sanitize_keys(list)
    Array(list).map(&:to_s).select { |k| DashboardLayout::WIDGET_KEYS.include?(k) }.uniq
  end

  # Ensure the chosen slot is the only active one for this scope/company.
  def activate_slot(slot)
    rel = layout_scope == "platform" ?
      DashboardLayout.platform :
      DashboardLayout.for_company(layout_company_id)
    rel.where.not(slot: slot).update_all(is_active: false)

    layout = DashboardLayout.resolve(scope: layout_scope, company_id: layout_company_id, slot: slot)
    layout.name ||= default_slot_name(slot)
    layout.is_active = true
    layout.save!
  end

  def layout_scope
    current_user&.platform_admin? ? "platform" : "company"
  end

  def layout_company_id
    layout_scope == "platform" ? nil : current_company&.id
  end

  def default_slot_name(slot)
    "#{t('layout', default: 'Layout')} #{slot}"
  end

  def require_customize_access
    return if current_user&.platform_admin?
    return if current_user&.company_user&.company_admin?

    redirect_to dashboard_overview_path, alert: t("unauthorized", default: "You are not authorized to do this."), status: :see_other
  end
end
