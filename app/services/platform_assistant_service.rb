class PlatformAssistantService
  MAX_RESULTS_PER_TYPE = 5

  # Raised when the LLM call fails, so the caller can avoid charging credits
  # for a query that produced no real answer.
  class AssistantError < StandardError; end

  def initialize(company, user: nil)
    @company = company
    @user = user
    @provider = ENV.fetch("CAPA_QUESTIONNAIRE_PROVIDER", "openrouter").downcase
  end

  # Returns { answer:, sources: } on success. Raises AssistantError on failure
  # so the controller can skip/refund the credit charge.
  def ask(question)
    context = gather_context(question)
    answer = call_llm(question, context)
    { answer: answer, sources: context.map { |c| c[:label] } }
  rescue AssistantError
    raise
  rescue => e
    Rails.logger.error "PlatformAssistantService error: #{e.class} - #{e.message}"
    raise AssistantError, e.message
  end

  private

  # Reuses the same PgSearch multisearch index already populated for
  # Standards, Clauses, CAPAs, and Uploads (see SearchController), plus a
  # plain ILIKE search over Risks, Vendors, and Customer Commitments which
  # aren't multisearchable.
  def gather_context(question)
    results = []

    PgSearch.multisearch(question)
      .where(searchable_type: [ "Standard", "Clause", "Capa", "Upload" ])
      .limit(MAX_RESULTS_PER_TYPE * 4)
      .each do |doc|
        searchable = doc.searchable
        next unless searchable
        next unless belongs_to_company?(searchable)

        results << { label: describe(searchable), text: summarize(searchable) }
      end

    Risk.active.where(company_id: @company&.id).where("title ILIKE ?", "%#{question.split.first}%").limit(3).each do |risk|
      results << { label: "Risk: #{risk.title}", text: "#{risk.title} — #{risk.description} (status: #{risk.status})" }
    end

    Vendor.active.where(company_id: @company&.id).where("name ILIKE ?", "%#{question.split.first}%").limit(3).each do |vendor|
      results << { label: "Vendor: #{vendor.name}", text: "#{vendor.name} — risk level: #{vendor.risk_level}, category: #{vendor.category}" }
    end

    results.first(15)
  end

  def belongs_to_company?(searchable)
    case searchable
    when Standard
      @company && searchable.company_standards.exists?(company_id: @company.id)
    when Clause
      standard = searchable.standard_version&.standard
      standard && @company && standard.company_standards.exists?(company_id: @company.id)
    when Capa
      searchable.company_id == @company&.id
    when Upload
      # Company-scoped AND respects per-upload visibility so private uploads
      # owned by other members never appear in AI answers/sources.
      searchable.company_id == @company&.id && searchable.visible_to_user?(@user)
    else
      true
    end
  end

  def describe(searchable)
    "#{searchable.class.name}: #{summarize(searchable).truncate(60)}"
  end

  def summarize(searchable)
    case searchable
    when Standard then searchable.display_name("en") || searchable.code
    when Clause then "#{searchable.full_code} #{searchable.title('en')}"
    when Capa then "#{searchable.friendly_code} — #{searchable.title}"
    when Upload then searchable.display_name
    else searchable.to_s
    end
  end

  def call_llm(question, context)
    context_text = context.map { |c| "- #{c[:text]}" }.join("\n")
    prompt = <<~PROMPT
      You are a compliance assistant for a Quality Management System. Answer the
      user's question using ONLY the context below. If the context doesn't
      contain the answer, say you don't have enough information.

      Context:
      #{context_text.presence || "(no matching records found)"}

      Question: #{question}
    PROMPT

    prompt = AiInstructionContext.decorate(prompt, company: @company, locale: I18n.locale)

    answer =
      if @provider == "openrouter"
        call_openrouter(prompt)
      else
        call_ollama(prompt)
      end

    raise AssistantError, "Empty response from language model" if answer.blank?

    answer
  end

  def call_openrouter(prompt)
    model = ENV["OPENROUTER_MODEL"].presence || "anthropic/claude-sonnet-4.5"
    Rails.logger.info "PlatformAssistant: provider=openrouter model=#{model}"

    OpenRouter.configure do |config|
      config.access_token = ENV.fetch("OPENROUTER_API_KEY")
      config.site_name = "Way to Excellence"
      config.site_url = ENV.fetch("APP_URL", "http://localhost:3000")
    end

    response = OpenRouter::Client.new.complete(
      [ { role: "user", content: prompt } ],
      model: model
    )

    # Surface the real provider error instead of a generic "empty response".
    raise AssistantError, "OpenRouter returned nil" if response.nil?
    if response.is_a?(Hash) && response["error"]
      message = response.dig("error", "message") || response["error"].inspect
      Rails.logger.error "PlatformAssistant OpenRouter error: #{message}"
      raise AssistantError, "OpenRouter error: #{message}"
    end

    content = response.dig("choices", 0, "message", "content").to_s.strip
    if content.blank?
      Rails.logger.error "PlatformAssistant OpenRouter empty content. Raw: #{response.inspect.truncate(500)}"
      raise AssistantError, "OpenRouter returned no content"
    end
    content
  end

  def call_ollama(prompt)
    model = ENV.fetch("CAPA_QUESTIONNAIRE_OLLAMA_MODEL", "qwen-capa-questionnaire")
    url = ENV["OLLAMA_URL"]
    Rails.logger.info "PlatformAssistant: provider=ollama model=#{model} url=#{url.presence || '(unset)'}"
    OllamaClient.new(model: model).generate(prompt).to_s.strip
  end
end
