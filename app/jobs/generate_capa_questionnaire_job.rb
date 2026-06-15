class GenerateCapaQuestionnaireJob
  include Sidekiq::Job

  sidekiq_options queue: :default, retry: 3

  def perform(capa_id, user_id = nil)
    capa = Capa.find_by(id: capa_id)

    unless capa
      Rails.logger.error "CAPA not found for questionnaire generation: #{capa_id}"
      return
    end

    begin
      # TODO: Check credits before generation (placeholder)
      # credits_needed = 2
      # unless has_sufficient_credits?(capa.company, credits_needed)
      #   raise "Insufficient credits. Need #{credits_needed} credits."
      # end

      service = CapaQuestionnaireService.new(capa)
      questionnaire_data = service.generate

      # Create questionnaire record
      if capa.questionnaire
        capa.questionnaire.update!(questionnaire_data)
      else
        capa.create_questionnaire(questionnaire_data)
        # Audit logging is handled by the controller when the questionnaire is created
      end

      # TODO: Deduct credits after successful generation (placeholder)
      # deduct_credits(capa.company, credits_needed)

      Rails.logger.info "Questionnaire generated successfully for CAPA #{capa.id}"
    rescue => e
      # Log error but don't fail the job - allow retries
      Rails.logger.error "Failed to generate questionnaire for CAPA #{capa.id}: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      # Re-raise to trigger Sidekiq retry mechanism
      raise
    end
  end
end
