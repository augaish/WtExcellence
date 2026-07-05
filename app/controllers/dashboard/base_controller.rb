class Dashboard::BaseController < ApplicationController
    layout "dashboard"

    before_action :set_current_user_for_activity_logging
    before_action :set_notifications_for_navbar
    after_action :clear_current_user_for_activity_logging

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

    helper_method :current_company, :current_company_user, :viewer?

    protected

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

    # Set current user in Thread storage for activity logging in model callbacks
    def set_current_user_for_activity_logging
        Thread.current[:current_user] = current_user
    end

    def set_notifications_for_navbar
        return unless current_user
        @recent_notifications = current_user.notifications.recent.limit(25)
        @unread_notifications_count = current_user.notifications.unread.count
    end

    # Clean up thread-local variable after request
    def clear_current_user_for_activity_logging
        Thread.current[:current_user] = nil
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
