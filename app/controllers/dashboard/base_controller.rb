class Dashboard::BaseController < ApplicationController
    layout "dashboard"

    around_action :with_current_user_for_activity_logging
    before_action :set_notifications_for_navbar

    # Get the current company based on the logged-in user
    # For non-platform-admin users, uses their company (users belong to exactly one company)
    # For platform admins (super_admin / delegated_admin), defaults to first active company
    # TODO: Replace with proper session/authentication-based company selection
    def current_company
        return @current_company if defined?(@current_company)

        if current_user&.platform_admin?
            @current_company = Company.active.order(:created_at).first
        else
            # Get the user's company (users belong to exactly one company)
            company_user = current_user&.company_user
            @current_company = company_user&.company
        end
    end

    # Get the current company user (defaults to admin@example.com for the current company)
    # This will be used everywhere in CAPA management
    def current_company_user
        return nil unless current_company

        @current_company_user ||= begin
            if current_user&.platform_admin?
                current_company.admin_company_user
            else
                current_user&.company_user
            end
        end
    end

    helper_method :current_company, :current_company_user, :viewer?, :module_enabled_for_current?

    # Class macro: gate an entire controller (or a subset via before_action
    # options) behind a per-company module. Platform admins always pass.
    #
    #   requires_module :capa
    #   requires_module :standards, except: [ :public_action ]
    def self.requires_module(key, **opts)
      before_action(**opts) { ensure_module_enabled(key) }
    end

    protected

    # Whether the current user's company has the module enabled. Platform admins
    # (super/delegated) and users without a company are never gated (true).
    def module_enabled_for_current?(key)
      return true if current_user&.platform_admin?

      company = current_user&.company
      company.nil? || company.module_enabled?(key)
    end

    # before_action guard: block access to a disabled module server-side, so a
    # hidden sidebar link can't be bypassed by typing the URL.
    def ensure_module_enabled(key)
      return if module_enabled_for_current?(key)

      respond_to do |format|
        format.html do
          redirect_to dashboard_overview_path,
            alert: t("modules.disabled_flash"), status: :see_other
        end
        format.json do
          render json: { success: false, error: "module_disabled", message: t("modules.disabled_flash") },
            status: :forbidden
        end
        format.any do
          redirect_to dashboard_overview_path, alert: t("modules.disabled_flash"), status: :see_other
        end
      end
    end

    # Role-based CAPA visibility (shared by Overview and CAPA Management).
    # Contributor: only CAPAs assigned to them.
    # Auditor: CAPAs assigned to them OR created by them.
    # QM & Company Admin: all CAPAs in company.
    def capa_visible_scope(base: nil)
      base ||= Capa.where(company_id: current_company&.id)
      return base unless current_company

      if current_user&.platform_admin?
        return base
      end

      cu = current_user&.company_user
      return base.none unless cu

      if cu.company_admin? || cu.company_quality_manager? || cu.company_viewer?
        return base
      end

      if cu.has_admin_privileges?
        return base
      end

      if cu.company_contributor?
        return base.joins(:capa_assignments).where(capa_assignments: { company_user_id: cu.id }).distinct
      end

      if cu.company_auditor?
        return base.left_joins(:capa_assignments).where(
          "capas.created_by_id = ? OR capa_assignments.company_user_id = ?",
          current_user.id,
          cu.id
        ).distinct
      end

      # viewer or other roles: only assigned to them
      base.joins(:capa_assignments).where(capa_assignments: { company_user_id: cu.id }).distinct
    end

    # Check if current user is a viewer (read-only role)
    def viewer?
      current_user&.company_user&.company_viewer?
    end

    # Prevent viewers from performing modification actions
    def prevent_viewer_action
      return false unless viewer?

      respond_to do |format|
        format.html do
          redirect_back(fallback_location: root_path,
                        alert: "You have read-only access and cannot perform this action",
                        status: :forbidden)
        end
        format.json do
          render json: {
            success: false,
            error: "You have read-only access and cannot perform this action"
          }, status: :forbidden
        end
      end
      true
    end

    # Alias for before_action usage (plural form)
    def prevent_viewer_actions
      prevent_viewer_action
    end

    # Risk Managers are scoped to Risk Management only — block them from
    # CAPA, Standards, and Library controllers even via direct URL access.
    def ensure_not_risk_manager_only
      return unless current_user&.risk_manager_only?

      respond_to do |format|
        format.html { redirect_to dashboard_risk_management_index_path, alert: "Your role is limited to Risk Management.", status: :see_other }
        format.json { render json: { success: false, error: "Your role is limited to Risk Management." }, status: :forbidden }
      end
    end

    # Null out an owner_id that doesn't belong to the current company, so a
    # crafted request can't attach another tenant's CompanyUser as owner.
    def sanitize_company_owner!(record)
      return unless record.respond_to?(:owner_id) && record.owner_id.present?

      valid = current_company&.company_users&.exists?(id: record.owner_id)
      record.owner_id = nil unless valid
    end

    # Shared permission guards for the GRC modules. Each denies with a proper
    # 303 redirect (browsers/Turbo follow 3xx, not 403+Location) or 403 JSON.
    def ensure_can_view_governance
      deny_grc_access(t("grc.no_permission_view")) unless current_user&.can_view_governance?
    end

    def ensure_can_manage_risks
      deny_grc_access(t("grc.no_permission_risks")) unless current_user&.can_manage_risks?
    end

    def ensure_can_manage_vendors
      deny_grc_access(t("grc.no_permission_vendors")) unless current_user&.can_manage_vendors?
    end

    def ensure_can_manage_commitments
      deny_grc_access(t("grc.no_permission_commitments")) unless current_user&.can_manage_commitments?
    end

    def deny_grc_access(message)
      respond_to do |format|
        format.html { redirect_to dashboard_capa_management_path, alert: message, status: :see_other }
        format.json { render json: { success: false, error: message }, status: :forbidden }
      end
    end

    private

    # A server-side rejection redirects back to the page, which used to arrive
    # with an empty form: fixing one field meant retyping every other. The
    # submitted values ride the redirect in the flash and are read back by the
    # `retained` helper, so the user corrects one thing and resubmits.
    def retain_form_values(scope, values)
      flash[:retained_form] = { scope.to_s => values.to_h.stringify_keys }
    end

    # Makes the acting user available to model callbacks that record activity.
    #
    # This was a before_action paired with an after_action, which leaks: an
    # after_action does not run when a before_action halts the chain — every
    # permission redirect does — nor when the action raises. Puma reuses
    # threads between requests, so the next request served by that thread could
    # attribute its changes to the previous request's user. An around_action
    # with ensure clears it on every path out.
    def with_current_user_for_activity_logging
        Thread.current[:current_user] = current_user
        yield
    ensure
        Thread.current[:current_user] = nil
    end

    def set_notifications_for_navbar
        return unless current_user
        @recent_notifications = current_user.notifications.recent.limit(25)
        @unread_notifications_count = current_user.notifications.unread.count
    end

    def require_company_admin
        return if current_user&.platform_admin?
        company_user = current_user&.company_user
        return if company_user&.company_admin?

        redirect_to dashboard_capa_management_path,
                    alert: "You don't have permission to manage AI credits.",
                    status: :see_other
        nil
    end
end
