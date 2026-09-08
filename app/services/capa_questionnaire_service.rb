class CapaQuestionnaireService
  def initialize(capa)
    @capa = capa
    @provider = ENV.fetch("CAPA_QUESTIONNAIRE_PROVIDER", "openrouter").downcase

    if @provider == "openrouter"
      # Configure OpenRouter
      OpenRouter.configure do |config|
        config.access_token = ENV.fetch("OPENROUTER_API_KEY")
        config.site_name = "Way to Excellence"
        config.site_url = ENV.fetch("APP_URL", "http://localhost:3000")
      end

      @client = OpenRouter::Client.new
      @model = ENV["OPENROUTER_MODEL"].presence || "anthropic/claude-sonnet-4.5"
      Rails.logger.info "Using OpenRouter with model: #{@model} for CAPA questionnaire generation"
    else
      # Use Ollama
      ollama_url = ENV.fetch("OLLAMA_URL", "http://localhost:11434")
      @ollama_url = ollama_url
      @ollama_model = ENV.fetch("CAPA_QUESTIONNAIRE_OLLAMA_MODEL", "qwen-capa-questionnaire")
      @ollama_single_pair_model = ENV.fetch("CAPA_QUESTIONNAIRE_SINGLE_PAIR_OLLAMA_MODEL", "qwen-capa-questionnaire-single")
      @ollama_root_cause_model = ENV.fetch("CAPA_ROOT_CAUSE_OLLAMA_MODEL", "qwen-capa-root-cause")
      # Use non-zero temperature/top_p so responses vary; server-side Ollama settings are overridden by the API request
      @ollama_temperature = (ENV["CAPA_QUESTIONNAIRE_TEMPERATURE"] || "0.6").to_f
      @ollama_top_p = (ENV["CAPA_QUESTIONNAIRE_TOP_P"] || "0.9").to_f
      Rails.logger.info "Using Ollama for CAPA questionnaire generation (temperature=#{@ollama_temperature}, top_p=#{@ollama_top_p})"
    end
  end

  def generate
    begin
      if @provider == "openrouter"
        prompt = build_prompt
        raw_text = call_openrouter_api(prompt)
      else
        prompt = build_user_prompt
        raw_text = call_ollama_api(prompt, @ollama_model)
      end
      cleaned_text = clean_response_text(raw_text)
      parsed_data = JSON.parse(cleaned_text)

      # Validate the structure
      validate_questionnaire_structure(parsed_data)

      parsed_data
    rescue JSON::ParserError => e
      Rails.logger.error "JSON parse error in questionnaire generation: #{e.message}"
      Rails.logger.error "Raw response: #{raw_text.inspect}" if defined?(raw_text)
      raise "Failed to parse questionnaire response: #{e.message}"
    rescue => e
      Rails.logger.error "Error generating questionnaire: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      raise
    end
  end

  # One quiet retry: a cut-off reply is transient far more often than not, and
  # a second attempt costs less than a user losing their place.
  def generate_single_pair(question_number, existing_questions = {})
    attempts = 0
    begin
      attempts += 1
      generate_single_pair_once(question_number, existing_questions)
    rescue JSON::ParserError, LlmResponse::Empty => e
      raise if attempts >= 2 || (e.is_a?(LlmResponse::Empty) && e.reason == :provider_error)

      Rails.logger.warn "Retrying question #{question_number} after: #{e.message}"
      retry
    end
  end

  def generate_single_pair_once(question_number, existing_questions = {})
    begin
      if @provider == "openrouter"
        prompt = build_single_pair_prompt(question_number, existing_questions)
        raw_text = call_openrouter_api(prompt)
      else
        prompt = build_single_pair_user_prompt(question_number, existing_questions)
        raw_text = call_ollama_api(prompt, @ollama_single_pair_model)
      end
      cleaned_text = clean_response_text(raw_text)
      parsed_data = JSON.parse(cleaned_text)

      # Validate the structure
      validate_single_pair_structure(parsed_data)

      parsed_data
    rescue JSON::ParserError => e
      Rails.logger.error "JSON parse error in single pair generation: #{e.message}"
      Rails.logger.error "Raw response: #{raw_text.inspect}" if defined?(raw_text)
      raise "Failed to parse question-answer pair response: #{e.message}"
    rescue => e
      Rails.logger.error "Error generating single pair: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      raise
    end
  end

  def generate_root_cause_summary(questionnaire)
    begin
      if @provider == "openrouter"
        prompt = build_root_cause_prompt(questionnaire)
        raw_text = call_openrouter_api(prompt)
      else
        prompt = build_root_cause_user_prompt(questionnaire)
        raw_text = call_ollama_api(prompt, @ollama_root_cause_model)
      end
      cleaned_text = clean_response_text(raw_text)
      parsed_data = JSON.parse(cleaned_text)

      validate_root_cause_structure(parsed_data)

      parsed_data["root_cause"]
    rescue JSON::ParserError => e
      Rails.logger.error "JSON parse error in root cause generation: #{e.message}"
      Rails.logger.error "Raw response: #{raw_text.inspect}" if defined?(raw_text)
      raise "Failed to parse root cause response: #{e.message}"
    rescue => e
      Rails.logger.error "Error generating root cause: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      raise
    end
  end

  private

  def build_prompt
    prompt_file = Rails.root.join("app", "services", "prompts", "capa_questionnaire_prompt.txt")
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

    prompt
  end

  def build_root_cause_prompt(questionnaire)
    prompt_file = Rails.root.join("app", "services", "prompts", "capa_root_cause_prompt.txt")
    prompt_template = File.read(prompt_file)

    capa_context = {
      "{{CAPA_TITLE}}" => @capa.title || "",
      "{{CAPA_DESCRIPTION}}" => @capa.description || "",
      "{{CAPA_SOURCE}}" => @capa.source&.humanize || "",
      "{{CAPA_PRIORITY}}" => @capa.priority&.humanize || ""
    }

    prompt = prompt_template
    capa_context.each do |placeholder, value|
      prompt = prompt.gsub(placeholder, value)
    end

    if @capa.standard.present?
      standard_name = @capa.standard.display_name || @capa.standard.code || ""
      standard_description = @capa.standard.description || ""

      standard_info = "- Related Standard: #{standard_name}"
      standard_info += "\n  Standard Description: #{standard_description}" if standard_description.present?

      prompt = prompt.gsub("{{STANDARD_INFO}}", standard_info)
    else
      prompt = prompt.gsub("{{STANDARD_INFO}}\n", "")
    end

    question_answer_pairs = (1..5).map do |num|
      question = questionnaire.send("question_#{num}")
      answer = questionnaire.send("answer_#{num}")
      next if question.blank? || answer.blank?

      "Question #{num}: #{question}\nAnswer #{num}: #{answer}"
    end.compact.join("\n\n")

    prompt.gsub("{{QUESTION_ANSWER_PAIRS}}", question_answer_pairs.presence || "No questionnaire responses provided.")
  end

  def call_openrouter_api(prompt)
    begin
      prompt = AiInstructionContext.decorate(prompt, company: @capa&.company, locale: I18n.locale)
      Rails.logger.info "Calling OpenRouter API for questionnaire generation"
      Rails.logger.info "Prompt length: #{prompt.length} chars"

      messages = [
        {
          role: "system",
          content: "You are an expert in quality management and root cause analysis. Always respond with valid JSON only, no markdown code blocks, no explanations."
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

  def call_ollama_api(prompt, model_name = nil)
    begin
      prompt = AiInstructionContext.decorate(prompt, company: @capa&.company, locale: I18n.locale)
      model_name ||= @ollama_model
      client = OllamaClient.new(model: model_name, base_url: @ollama_url)

      Rails.logger.info "Calling Ollama API for questionnaire generation with model: #{model_name}"
      Rails.logger.info "Prompt length: #{prompt.length} chars"

      response = client.generate(
        prompt,
        max_tokens: 8000,
        temperature: @ollama_temperature,
        top_p: @ollama_top_p
      )

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
    user_prompt = "CAPA Details:\n"
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

    # Language instruction based on current locale
    case I18n.locale.to_s
    when "ar"
      user_prompt += "IMPORTANT: Write all questions, answers, and the root cause summary in Arabic.\n\n"
    else
      user_prompt += "IMPORTANT: Write all questions, answers, and the root cause summary in English.\n\n"
    end

    user_prompt += "Generate a structured 5 Why analysis questionnaire that will help identify the root cause of the issue described in this CAPA.\n\n"
    user_prompt += "Generate the questionnaire now:"
    user_prompt
  end

  def build_single_pair_user_prompt(question_number, existing_questions = {})
    # Build the user prompt with actual CAPA data (system prompt is in the model)
    user_prompt = "CAPA Details:\n"
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

    # Language instruction based on current locale
    case I18n.locale.to_s
    when "ar"
      user_prompt += "IMPORTANT: Write this question and answer in Arabic.\n\n"
    else
      user_prompt += "IMPORTANT: Write this question and answer in English.\n\n"
    end

    # Handle previous questions if any
    if existing_questions.any? && question_number > 1
      user_prompt += "Previously accepted questions and answers:\n"
      existing_questions.each do |num, qa|
        user_prompt += "Question #{num}: #{qa[:question]}\n"
        user_prompt += "Answer #{num}: #{qa[:answer]}\n\n"
      end
    end

    user_prompt += "You are generating Question #{question_number} of 5 for the 5 Why analysis.\n\n"
    user_prompt += "Generate the question-answer pair now:"
    user_prompt
  end

  def build_root_cause_user_prompt(questionnaire)
    # Build the user prompt with actual CAPA data and questionnaire responses (system prompt is in the model)
    user_prompt = "CAPA Context:\n"
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

    # Language instruction based on current locale
    case I18n.locale.to_s
    when "ar"
      user_prompt += "IMPORTANT: Write the root cause summary in Arabic.\n\n"
    else
      user_prompt += "IMPORTANT: Write the root cause summary in English.\n\n"
    end

    user_prompt += "Questionnaire Responses:\n"

    question_answer_pairs = (1..5).map do |num|
      question = questionnaire.send("question_#{num}")
      answer = questionnaire.send("answer_#{num}")
      next if question.blank? || answer.blank?

      "Question #{num}: #{question}\nAnswer #{num}: #{answer}"
    end.compact.join("\n\n")

    user_prompt += question_answer_pairs.presence || "No questionnaire responses provided."
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

  def build_single_pair_prompt(question_number, existing_questions = {})
    prompt_file = Rails.root.join("app", "services", "prompts", "capa_questionnaire_single_pair_prompt.txt")
    prompt_template = File.read(prompt_file)

    # Build CAPA context
    capa_context = {
      "{{CAPA_TITLE}}" => @capa.title || "",
      "{{CAPA_DESCRIPTION}}" => @capa.description || "",
      "{{CAPA_SOURCE}}" => @capa.source&.humanize || "",
      "{{CAPA_PRIORITY}}" => @capa.priority&.humanize || "",
      "{{QUESTION_NUMBER}}" => question_number.to_s
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

    # Handle previous questions if any
    if existing_questions.any? && question_number > 1
      previous_questions_text = "Previously accepted questions and answers:\n"
      existing_questions.each do |num, qa|
        previous_questions_text += "Question #{num}: #{qa[:question]}\n"
        previous_questions_text += "Answer #{num}: #{qa[:answer]}\n"
        previous_questions_text += "\n"
      end

      prompt = prompt.gsub("{{PREVIOUS_QUESTIONS}}", previous_questions_text)
    else
      # Remove previous questions placeholder if none
      prompt = prompt.gsub("{{PREVIOUS_QUESTIONS}}\n", "")
    end

    prompt
  end

  def validate_questionnaire_structure(data)
    required_fields = %w[question_1 question_2 question_3 question_4 question_5
                        answer_1 answer_2 answer_3 answer_4 answer_5
                        root_cause]

    missing_fields = required_fields - data.keys

    if missing_fields.any?
      raise "Missing required fields in questionnaire: #{missing_fields.join(', ')}"
    end

    # Validate that all fields have non-empty values
    required_fields.each do |field|
      if data[field].blank?
        raise "Field #{field} is empty"
      end
    end
  end

  def validate_single_pair_structure(data)
    unless data.is_a?(Hash)
      raise "Response must be a JSON object"
    end

    unless data["question"].present?
      raise "Missing 'question' field in response"
    end

    unless data["answer"].present?
      raise "Missing 'answer' field in response"
    end
  end

  def validate_root_cause_structure(data)
    unless data.is_a?(Hash)
      raise "Response must be a JSON object"
    end

    unless data["root_cause"].present?
      raise "Missing 'root_cause' field in response"
    end
  end
end
