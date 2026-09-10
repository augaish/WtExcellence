# The company's activity: every create, change and deletion, and the actions
# the app records on top of them (sign-ins, invitations, approvals). Read by
# the people who manage the company; exported as a sheet for an auditor.
class Dashboard::ActivityLogsController < Dashboard::BaseController
  before_action :authenticate_user!
  before_action :ensure_can_read_activity

  PAGE_SIZE = 50

  def index
    @filter = ActivityFilter.new(company, params)
    @pagy, @entries = pagy(@filter.scope.includes(:actor_user), items: PAGE_SIZE)
    @actors = company.users.order(:name).to_a
  end

  def export
    @filter = ActivityFilter.new(company, params)
    send_data ActivityExport.new(@filter.scope.includes(:actor_user).limit(10_000).to_a, view_context).to_xlsx,
      filename: "activity_#{company.name.parameterize}_#{Date.current}.xlsx",
      type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  end

  private

  def company
    @company ||= current_company
  end

  # Admins and the managers read it; contributors and viewers do not.
  def ensure_can_read_activity
    return if company && can_read_activity?

    redirect_to dashboard_general_settings_path, alert: t("activity.not_permitted"), status: :see_other
  end

  def can_read_activity?
    return true if current_user&.platform_admin?

    membership = current_user&.company_user
    membership.present? && (membership.has_admin_privileges? || membership.company_quality_manager? || membership.company_risk_manager?)
  end
end
