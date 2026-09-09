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

  # What the product actually contains. The assistant was answering "how do I…"
  # questions by inventing plausible controls — "Related Items", "Link Existing
  # Risk" — that do not exist, which sends a user hunting for a button that was
  # never built. Listing the real areas is what stops that; the guard test keeps
  # this in step with Company::MODULES.
  PRODUCT_MAP = {
    "library" => "Library — upload documents and link them as evidence to standards, CAPAs, risks, vendors, commitments and records.",
    "org_structure" => "Org Structure — organizational units across six levels, with mandates, heads and colour groups. Has a list view and a chart view.",
    "standards" => "Standards — assess clauses and checkpoints against ingested standards.",
    "capa" => "CAPA Management — corrective and preventive actions, with a questionnaire, root cause and generated actions.",
    "processes" => "Process Architecture — Level 0 bands, Level 1 and Level 2 processes, as a list or a model; procedures are level 3 and live in Records.",
    "pp" => "Policies & Procedures — Records (policies, procedures, forms, services, glossary) and Packages, the Documenter lifecycle with its approvals and publishing, and Efficiency Evaluation. Any record can be viewed as a branded printable document or PDF.",
    "authorities" => "Authorities & Delegations — the executive authority matrix by category, with holders per level, delegations, a review round and a published version.",
    "risk" => "Risk Management — a risk register scored on a 5x5 likelihood by impact matrix, with inherent, current residual and target exposure, and a company risk appetite.",
    "vendors" => "Vendor Management — vendors with a risk level, category and owner.",
    "commitments" => "Customer Commitments — obligations with due dates, where timing is derived from the due date rather than chosen.",
    "trust_center" => "Trust Center — publishes what the company chooses to share externally.",
    "ai_instructions" => "AI Instructions — company-specific guidance applied to AI answers.",
    "tools" => "Tool Setup — checkpoint and scoring configuration."
  }.freeze

  def call_llm(question, context)
    context_text = context.map { |c| "- #{c[:text]}" }.join("\n")
    prompt = <<~PROMPT
      You are a knowledgeable assistant for Way to Excellence, a Quality
      Management System (QMS) and compliance platform. You handle two kinds of
      questions:

      1. General quality-management, standards, and compliance knowledge — e.g.
         what EFQM, ISO 9001, or a CAPA is; how root-cause analysis works.
         Answer these clearly from your own expertise, even when the context
         below is empty.

      2. Questions about THIS company's own records (standards, clauses, CAPAs,
         risks, vendors, documents). Answer these using the context below. If a
         specific record isn't present, say you don't have that item in the
         company's data — never invent company-specific facts, names, or numbers.

      3. Questions about how to DO something in this platform. Answer these
         only from the product map below. Never invent a screen, button, tab or
         control: if the map does not show a way to do what was asked, say the
         platform does not appear to offer it and suggest the closest thing that
         does exist, or point the user to the in-app manual under Help. A
         confident answer naming a control that was never built costs the user
         more time than admitting the gap.

      When a question mixes these, combine your general knowledge with the
      company context. Prefer the company context whenever it is relevant.

      Product map — the areas this platform actually has:
      #{PRODUCT_MAP.values.map { |line| "- #{line}" }.join("\n")}

      Company context:
      #{context_text.presence || "(no matching company records found for this question)"}

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
