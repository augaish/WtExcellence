module SettingsHelper
  # The Documenter tab of Settings is for the people who run the lifecycle:
  # platform admins, company admins and quality managers.
  # Activity is read by admins and the managers, never by contributors or viewers.
  def can_read_activity_tab?
    return true if current_user&.platform_admin?

    cu = current_user&.company_user
    cu.present? && (cu.has_admin_privileges? || cu.company_quality_manager? || cu.company_risk_manager?)
  end

  def can_manage_documenter_settings?
    return true if current_user&.platform_admin?

    cu = current_user&.company_user
    cu.present? && (cu.has_admin_privileges? || cu.company_quality_manager?)
  end
end
