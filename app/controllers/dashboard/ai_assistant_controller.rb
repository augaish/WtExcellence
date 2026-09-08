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

    # Platform admins operate above company credit accounting, so they aren't
    # gated or charged. Company members are checked against their balance.
    platform_admin = current_user&.platform_admin?
    company_user = current_company_user

    unless platform_admin
      unless company_user && CreditService.has_sufficient_credits?(current_company, "PLATFORM_ASSISTANT_QUERY", company_user: company_user)
        render json: { success: false, error: t("ai_assistant.insufficient_credits") }, status: :payment_required
        return
      end
    end

    # Run the query first; only charge credits once the LLM actually answers,
    # so an outage never silently bills the user.
    begin
      result = PlatformAssistantService.new(current_company, user: current_user).ask(question)
    rescue PlatformAssistantService::AssistantError => e
      # Show the underlying provider error to platform admins so AI config
      # issues (402 / invalid model / unreachable Ollama) are diagnosable in-app;
      # ordinary users still get the generic message.
      error_message = platform_admin ? "#{t('ai_assistant.failed')} (#{e.message})" : t("ai_assistant.failed")
      render json: { success: false, error: error_message }, status: :bad_gateway
      return
    end

    charged = !platform_admin
    CreditService.deduct_credits(current_company, "PLATFORM_ASSISTANT_QUERY", company_user: company_user) if charged

    # credits_used is recorded explicitly, as the other charged actions do, so
    # the usage screens report what the balance was actually reduced by.
    AuditLogService.log_action(
      actor_user: current_user,
      company: current_company,
      action: "PLATFORM_ASSISTANT_QUERY",
      entity_type: "ai_assistant",
      entity_id: nil,
      payload: {
        question: question,
        source_count: result[:sources].size,
        credits_used: charged ? CreditService.get_cost("PLATFORM_ASSISTANT_QUERY") : 0
      }
    )

    render json: { success: true, answer: result[:answer], sources: result[:sources] }
  end

  private

  # Mirror the widget's visibility: platform admins (who have no company_user)
  # and any non-contributor company member may use the assistant.
  def ensure_assistant_access
    return if current_user&.platform_admin?
    return if current_user&.company_user.present? && !current_user&.company_contributor?

    render json: { success: false, error: t("ai_assistant.no_access") }, status: :forbidden
  end
end
