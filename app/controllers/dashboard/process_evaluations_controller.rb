class Dashboard::ProcessEvaluationsController < Dashboard::BaseController
  requires_module :pp
  before_action :authenticate_user!
  before_action :ensure_company_present

  # Pick a saved diagram to evaluate.
  def index
    @diagrams = company.pp_diagrams.includes(:owner).recent_first.to_a
  end

  def show
    @diagram = company.pp_diagrams.includes(:elements, :flows).find_by(id: params[:id])
    unless @diagram
      return redirect_to dashboard_process_evaluations_path, alert: t("architect.flash.not_found"), status: :see_other
    end

    @result = ProcessEvaluationService.evaluate_diagram(@diagram)
    @recommendations = sort_by_priority(@result[:recommendations])

    # Cache the score so registers and widgets can show it without recomputing.
    @diagram.update_columns(last_score: @result[:score], last_evaluated_at: Time.current)
  end

  private

  def company
    @company ||= current_company
  end

  def ensure_company_present
    return if company

    redirect_to dashboard_overview_path, alert: t("pp_records.flash.no_company"), status: :see_other
  end

  # high -> medium -> low, as specified.
  def sort_by_priority(recommendations)
    order = ProcessEvaluationService::PRIORITIES
    recommendations.sort_by { |r| order.index(r[:priority]) || order.size }
  end
end
