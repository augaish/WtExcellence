class Dashboard::AiAssistantController < Dashboard::BaseController
  before_action :authenticate_user!
  before_action :ensure_not_risk_manager_only
  before_action :ensure_assistant_access

  def ask
    question = params[:question].to_s.strip

    if question.blank?
      render json: { success: false, error: t("ai_assistant.blank_question") }, status: :unprocessable_entity
      return
    end

    company_user = current_company_user
    unless company_user && CreditService.has_sufficient_credits?(current_company, "PLATFORM_ASSISTANT_QUERY", company_user: company_user)
      render json: { success: false, error: t("ai_assistant.insufficient_credits") }, status: :payment_required
      return
    end

    # Run the query first; only charge credits once the LLM actually answers,
    # so an outage never silently bills the user.
    begin
      result = PlatformAssistantService.new(current_company, user: current_user).ask(question)
    rescue PlatformAssistantService::AssistantError
      render json: { success: false, error: t("ai_assistant.failed") }, status: :bad_gateway
      return
    end

    CreditService.deduct_credits(current_company, "PLATFORM_ASSISTANT_QUERY", company_user: company_user)

    AuditLogService.log_action(
      actor_user: current_user,
      company: current_company,
      action: "PLATFORM_ASSISTANT_QUERY",
      entity_type: "ai_assistant",
      entity_id: nil,
      payload: { question: question, source_count: result[:sources].size }
    )

    render json: { success: true, answer: result[:answer], sources: result[:sources] }
  end

  private

  # Mirror the widget's visibility: only company members that are not
  # contributors may use the assistant (which summarizes CAPA/Standard/Upload
  # data the contributor role isn't meant to browse platform-wide).
  def ensure_assistant_access
    return if current_user&.company_user.present? && !current_user&.company_contributor?

    render json: { success: false, error: t("ai_assistant.no_access") }, status: :forbidden
  end
end
