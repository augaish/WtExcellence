class CapaClauseSuggestionService
  def initialize(capa, company)
    @capa = capa
    @company = company
    @provider = ENV.fetch("CAPA_CLAUSE_PROVIDER", "openrouter").downcase

    if @provider == "openrouter"
      # Configure OpenRouter
      OpenRouter.configure do |config|
        config.access_token = ENV.fetch("OPENROUTER_API_KEY")
        config.site_name = "Way to Excellence"
        config.site_url = ENV.fetch("APP_URL", "http://localhost:3000")
      end

      @client = OpenRouter::Client.new
      @model = ENV["OPENROUTER_MODEL"].presence || "anthropic/claude-sonnet-4.5"
      Rails.logger.info "Using OpenRouter with model: #{@model} for CAPA clause suggestion"
    else
      # Use Ollama
      ollama_url = ENV.fetch("OLLAMA_URL", "http://localhost:11434")
      @client = OllamaClient.new(
        model: ENV.fetch("CAPA_CLAUSE_OLLAMA_MODEL", "qwen-capa-clause"),
        base_url: ollama_url
      )
      Rails.logger.info "Using Ollama with model: #{ENV.fetch('CAPA_CLAUSE_OLLAMA_MODEL', 'qwen-capa-clause')} for CAPA clause suggestion"
    end
  end

  def suggest
    begin
      if @provider == "openrouter"
        prompt = build_prompt
        prompt = AiInstructionContext.decorate(prompt, company: @company, locale: I18n.locale)
        raw_text = call_openrouter_api(prompt)
      else
        prompt = build_user_prompt
        prompt = AiInstructionContext.decorate(prompt, company: @company, locale: I18n.locale)
        raw_text = call_ollama_api(prompt)
      end
      cleaned_text = clean_response_text(raw_text)
      parsed_data = JSON.parse(cleaned_text)

      # Validate the structure
      validate_suggestions_structure(parsed_data)

      parsed_data
    rescue JSON::ParserError => e
      Rails.logger.error "JSON parse error in clause suggestion: #{e.message}"
      Rails.logger.error "Raw response: #{raw_text.inspect}" if defined?(raw_text)
      raise "Failed to parse suggestions response: #{e.message}"
    rescue => e
      Rails.logger.error "Error generating clause suggestions: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      raise
    end
  end

  private

  def build_prompt
    prompt_file = Rails.root.join("app", "services", "prompts", "capa_clause_suggestion_prompt.txt")
    prompt_template = File.read(prompt_file)

    # Build CAPA context
    capa_context = {
      "{{CAPA_TITLE}}" => @capa.title || "",
      "{{CAPA_DESCRIPTION}}" => @capa.description || "",
      "{{CAPA_SOURCE}}" => @capa.source&.humanize || "",
      "{{CAPA_PRIORITY}}" => @capa.priority&.humanize || ""
    }

    # Replace CAPA placeholders
    prompt = prompt_template
    capa_context.each do |placeholder, value|
      prompt = prompt.gsub(placeholder, value)
    end

    # Handle standard information if available
    if @capa.standard.present?
      standard_name = @capa.standard.display_name || @capa.standard.code || ""
      standard_description = @capa.standard.description || ""

      standard_info = "- Related Standard: #{standard_name}"
      standard_info += "\n  Standard Description: #{standard_description}" if standard_description.present?

      prompt = prompt.gsub("{{STANDARD_INFO}}", standard_info)
    else
      # Remove standard section placeholder if no standard
      prompt = prompt.gsub("{{STANDARD_INFO}}\n", "")
    end

    # Handle questionnaire information if exists
    if @capa.questionnaire.present?
      q = @capa.questionnaire
      questionnaire_info = "Questionnaire:\n"
      questionnaire_info += "Question 1: #{q.question_1}\n"
      questionnaire_info += "Answer 1: #{q.answer_1}\n"
      questionnaire_info += "\n"
      questionnaire_info += "Question 2: #{q.question_2}\n"
      questionnaire_info += "Answer 2: #{q.answer_2}\n"
      questionnaire_info += "\n"
      questionnaire_info += "Question 3: #{q.question_3}\n"
      questionnaire_info += "Answer 3: #{q.answer_3}\n"
      questionnaire_info += "\n"
      questionnaire_info += "Question 4: #{q.question_4}\n"
      questionnaire_info += "Answer 4: #{q.answer_4}\n"
      questionnaire_info += "\n"
      questionnaire_info += "Question 5: #{q.question_5}\n"
      questionnaire_info += "Answer 5: #{q.answer_5}\n"
      questionnaire_info += "\n"
      questionnaire_info += "Root Cause Summary: #{q.root_cause}\n"
      questionnaire_info += "\n"

      prompt = prompt.gsub("{{QUESTIONNAIRE_INFO}}", questionnaire_info)
    else
      # Remove questionnaire section placeholder if no questionnaire
      prompt = prompt.gsub("{{QUESTIONNAIRE_INFO}}\n", "")
    end

    # Handle existing linked clauses
    existing_clauses = @capa.clauses.includes(:standard_version, :clause_translations)
    if existing_clauses.any?
      existing_clauses_text = "Already Linked Clauses:\n"
      existing_clauses.each do |clause|
        standard = clause.standard_version&.standard
        existing_clauses_text += "- #{clause.code}: #{clause.title('en')} (#{standard&.display_name || 'N/A'})\n"
      end
      existing_clauses_text += "\n"

      prompt = prompt.gsub("{{EXISTING_CLAUSES}}", existing_clauses_text)
    else
      # Remove existing clauses section placeholder if none
      prompt = prompt.gsub("{{EXISTING_CLAUSES}}\n", "")
    end

    # Get available clauses for the company
    available_clauses = get_available_clauses
    if available_clauses.any?
      clauses_text = "Available Clauses (select the most relevant ones):\n"
      available_clauses.each do |clause|
        standard = clause.standard_version&.standard
        title = clause.title("en") || clause.code
        clauses_text += "- Code: #{clause.code}, Title: #{title}, Standard: #{standard&.display_name || 'N/A'}\n"
      end
      clauses_text += "\n"

      prompt = prompt.gsub("{{AVAILABLE_CLAUSES}}", clauses_text)
    else
      # Remove available clauses section placeholder if none
      prompt = prompt.gsub("{{AVAILABLE_CLAUSES}}\n", "")
    end

    prompt
  end

  def get_available_clauses
    # Get clauses from standards available to the company
    # Limit to a reasonable number to avoid overwhelming the prompt
    # Get clauses from company standards, excluding already linked ones
    linked_clause_ids = @capa.clauses.pluck(:id)

    Clause.joins(standard_version: { standard: :company_standards })
          .where(company_standards: { company_id: @company.id })
          .where.not(id: linked_clause_ids)
          .includes(:standard_version, :clause_translations, standard_version: :standard)
          .limit(200) # Limit to avoid token limits
          .order(:code)
  end

  def call_openrouter_api(prompt)
    begin
      Rails.logger.info "Calling OpenRouter API for clause suggestion"
      Rails.logger.info "Prompt length: #{prompt.length} chars"

      messages = [
        {
          role: "system",
          content: "You are an expert in quality management standards and compliance. Always respond with valid JSON only, no markdown code blocks, no explanations."
        },
        {
          role: "user",
          content: prompt
        }
      ]

      # Without a ceiling the reply can stop mid-JSON, which surfaced to users
      # as a parse error about a closing quote.
      response = @client.complete(
        messages,
        model: @model,
        extras: { max_tokens: ENV.fetch("CAPA_MAX_TOKENS", "4000").to_i }
      )

      # One reader for every reply, which names why a reply was unusable
      # instead of the generic "failed to extract content".
      content = LlmResponse.content!(response)

      Rails.logger.info "Successfully extracted content (#{content.length} chars)"
      content
    rescue => e
      Rails.logger.error "OpenRouter API call failed: #{e.class} - #{e.message}"
      Rails.logger.error "Backtrace: #{e.backtrace.first(5).join("\n")}"
      raise
    end
  end

  def call_ollama_api(prompt)
    begin
      Rails.logger.info "Calling Ollama API for clause suggestion"
      Rails.logger.info "Prompt length: #{prompt.length} chars"

      response = @client.generate(prompt, max_tokens: 8000)

      if response.nil?
        Rails.logger.error "Ollama API returned nil response"
        raise "API returned nil response"
      end

      Rails.logger.info "Successfully extracted content (#{response.length} chars)"
      response
    rescue => e
      Rails.logger.error "Ollama API call failed: #{e.class} - #{e.message}"
      Rails.logger.error "Backtrace: #{e.backtrace.first(5).join("\n")}"
      raise
    end
  end

  def build_user_prompt
    # Build the user prompt with actual CAPA data (system prompt is in the model)
    user_prompt = "CAPA Information:\n"
    user_prompt += "- Title: #{@capa.title || ''}\n"
    user_prompt += "- Description: #{@capa.description || ''}\n"
    user_prompt += "- Source: #{@capa.source&.humanize || ''}\n"
    user_prompt += "- Priority: #{@capa.priority&.humanize || ''}\n"

    # Handle standard information if available
    if @capa.standard.present?
      standard_name = @capa.standard.display_name || @capa.standard.code || ""
      standard_description = @capa.standard.description || ""
      user_prompt += "- Related Standard: #{standard_name}\n"
      user_prompt += "  Standard Description: #{standard_description}\n" if standard_description.present?
    end

    user_prompt += "\n"

    # Handle questionnaire information if exists
    if @capa.questionnaire.present?
      q = @capa.questionnaire
      user_prompt += "Questionnaire:\n"
      user_prompt += "Question 1: #{q.question_1}\n"
      user_prompt += "Answer 1: #{q.answer_1}\n\n"
      user_prompt += "Question 2: #{q.question_2}\n"
      user_prompt += "Answer 2: #{q.answer_2}\n\n"
      user_prompt += "Question 3: #{q.question_3}\n"
      user_prompt += "Answer 3: #{q.answer_3}\n\n"
      user_prompt += "Question 4: #{q.question_4}\n"
      user_prompt += "Answer 4: #{q.answer_4}\n\n"
      user_prompt += "Question 5: #{q.question_5}\n"
      user_prompt += "Answer 5: #{q.answer_5}\n\n"
      user_prompt += "Root Cause Summary: #{q.root_cause}\n\n"
    end

    # Handle existing linked clauses
    existing_clauses = @capa.clauses.includes(:standard_version, :clause_translations)
    if existing_clauses.any?
      user_prompt += "Already Linked Clauses:\n"
      existing_clauses.each do |clause|
        standard = clause.standard_version&.standard
        user_prompt += "- #{clause.code}: #{clause.title('en')} (#{standard&.display_name || 'N/A'})\n"
      end
      user_prompt += "\n"
    end

    # Get available clauses for the company
    available_clauses = get_available_clauses
    if available_clauses.any?
      user_prompt += "Available Clauses (select the most relevant ones):\n"
      available_clauses.each do |clause|
        standard = clause.standard_version&.standard
        title = clause.title("en") || clause.code
        user_prompt += "- Code: #{clause.code}, Title: #{title}, Standard: #{standard&.display_name || 'N/A'}\n"
      end
      user_prompt += "\n"
    end

    user_prompt += "Analyze the CAPA and suggest relevant clauses now:"
    user_prompt
  end

  def clean_response_text(text)
    # Remove markdown code blocks if present
    cleaned = text.strip

    # Remove ```json or ``` markers
    cleaned = cleaned.gsub(/^```json\s*$/i, "")
    cleaned = cleaned.gsub(/^```\s*$/i, "")
    cleaned = cleaned.strip

    # Remove any leading/trailing whitespace
    cleaned.strip
  end

  def validate_suggestions_structure(data)
    unless data.is_a?(Hash) && data["suggestions"].is_a?(Array)
      raise "Response must contain a 'suggestions' array"
    end

    suggestions = data["suggestions"]

    unless suggestions.length <= 10
      raise "Expected at most 10 suggestions, got #{suggestions.length}"
    end

    suggestions.each_with_index do |suggestion, index|
      unless suggestion.is_a?(Hash)
        raise "Suggestion #{index + 1} is not a valid object"
      end

      unless suggestion["clause_code"].present?
        raise "Suggestion #{index + 1} is missing clause_code"
      end

      unless suggestion["reasoning"].present?
        raise "Suggestion #{index + 1} is missing reasoning"
      end
    end
  end
end
