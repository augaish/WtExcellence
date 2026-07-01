class Dashboard::AiAssistantController < Dashboard::BaseController
  before_action :authenticate_user!

  def ask
    question = params[:question].to_s.strip

    if question.blank?
      render json: { success: false, error: "Please enter a question." }, status: :unprocessable_entity
      return
    end

    company_user = current_company_user
    unless company_user && CreditService.has_sufficient_credits?(current_company, "PLATFORM_ASSISTANT_QUERY", company_user: company_user)
      render json: { success: false, error: "Insufficient AI credits." }, status: :payment_required
      return
    end

    CreditService.deduct_credits(current_company, "PLATFORM_ASSISTANT_QUERY", company_user: company_user)

    result = PlatformAssistantService.new(current_company).ask(question)

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
end
