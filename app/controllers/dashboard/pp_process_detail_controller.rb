# Shared setup for the pieces edited on a procedure's detail page: its steps and
# its operational authority matrix. They share the process lookup and the same
# permission rule as the process itself, so it lives in one place.
class Dashboard::PpProcessDetailController < Dashboard::BaseController
  requires_module :pp
  before_action :authenticate_user!
  before_action :ensure_can_manage
  before_action :set_process

  private

  def company
    @company ||= current_company
  end

  def set_process
    @process = company&.pp_processes&.find_by(id: params[:pp_process_id])
    return if @process

    redirect_to dashboard_pp_processes_path, alert: t("process_architecture.flash.not_found"), status: :see_other
  end

  def can_manage_processes?
    return true if current_user&.platform_admin?

    membership = current_user&.company_user
    membership.present? && (membership.has_admin_privileges? || membership.company_quality_manager?)
  end

  def ensure_can_manage
    return if can_manage_processes?

    redirect_to dashboard_pp_processes_path, alert: t("process_architecture.flash.no_permission"), status: :see_other
  end

  def back_to_process(notice: nil, alert: nil)
    redirect_to dashboard_pp_process_path(@process), notice: notice, alert: alert, status: :see_other
  end
end
