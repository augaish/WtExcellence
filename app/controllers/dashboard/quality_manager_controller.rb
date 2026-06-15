class Dashboard::QualityManagerController < Dashboard::BaseController
  before_action :authenticate_user!
  before_action :ensure_quality_manager

  def index
    # Get assessments pending QM approval
    @pending_assignments = Assessment
      .where(company_id: current_company&.id, status: "under_review")
      .includes(tool_clause: { clause: { standard_version: :standard }, tool: [] })
      .order(updated_at: :desc)

    # Get recently approved assessments
    @recently_approved = Assessment
      .where(company_id: current_company&.id, status: "approved")
      .includes(tool_clause: { clause: { standard_version: :standard }, tool: [] })
      .order(updated_at: :desc)
      .limit(10)

    # Get statistics
    @total_pending = @pending_assignments.count
    @total_approved_today = Assessment
      .where(company_id: current_company&.id, status: "approved")
      .where("assessments.updated_at >= ?", Time.current.beginning_of_day)
      .count
    @total_approved_this_week = Assessment
      .where(company_id: current_company&.id, status: "approved")
      .where("assessments.updated_at >= ?", Time.current.beginning_of_week)
      .count
  end

  private

  def ensure_quality_manager
    unless current_user&.company_user&.company_quality_manager?
      redirect_to root_path, alert: "Access denied. Only Quality Managers can access this page."
    end
  end
end
