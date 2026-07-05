# Builds the company-specific instruction block that gets prepended to LLM
# prompts, so admin-provided domain knowledge (terminology, standards guidance)
# steers questionnaire/action/clause generation and the Ask-AI assistant.
class AiInstructionContext
  MAX_CHARS = 6_000

  # Returns a formatted context string for a company, or nil when there are no
  # active instructions. `locale` selects which language's content to use.
  def self.for_company(company, locale: I18n.locale)
    return nil unless company

    blocks = company.ai_instructions.active.order(:created_at).filter_map do |instruction|
      body = instruction.content_for(locale)
      next if body.blank?

      "## #{instruction.title}\n#{body.strip}"
    end

    return nil if blocks.empty?

    context = blocks.join("\n\n")
    context = "#{context[0, MAX_CHARS]}…" if context.length > MAX_CHARS
    context
  rescue => e
    # Never let instruction loading break an AI call.
    Rails.logger.error "AiInstructionContext error: #{e.class} - #{e.message}"
    nil
  end

  # Prepends the company context to an existing prompt string. No-op when there
  # are no instructions, so callers can wrap unconditionally.
  def self.decorate(prompt, company:, locale: I18n.locale)
    context = for_company(company, locale: locale)
    return prompt if context.blank?

    <<~DECORATED
      Company-specific context (authoritative — prefer this over general knowledge when relevant):
      #{context}

      ---

      #{prompt}
    DECORATED
  end
end
