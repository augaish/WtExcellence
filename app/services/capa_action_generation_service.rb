class CapaActionGenerationService
  def initialize(capa)
    @capa = capa
    @provider = ENV.fetch("CAPA_ACTION_PROVIDER", "ollama").downcase

    if @provider == "openrouter"
      # Configure OpenRouter
      OpenRouter.configure do |config|
        config.access_token = ENV.fetch("OPENROUTER_API_KEY")
        config.site_name = "Way to Excellence"
        config.site_url = ENV.fetch("APP_URL", "http://localhost:3000")
      end

      @client = OpenRouter::Client.new
      @model = ENV.fetch("OPENROUTER_MODEL", "anthropic/claude-sonnet-4-20250514")
      Rails.logger.info "Using OpenRouter with model: #{@model} for CAPA action generation"
    else
      # Use Ollama
      ollama_url = ENV.fetch("OLLAMA_URL", "http://localhost:11434")
      @client = OllamaClient.new(
        model: ENV.fetch("CAPA_ACTION_OLLAMA_MODEL", "qwen-capa-action"),
        base_url: ollama_url
      )
      Rails.logger.info "Using Ollama with model: #{ENV.fetch('CAPA_ACTION_OLLAMA_MODEL', 'qwen-capa-action')} for CAPA action generation"
    end
  end

  def generate
    begin
      if @provider == "openrouter"
        prompt = build_prompt
        raw_text = call_openrouter_api(prompt)
      else
        prompt = build_user_prompt
        raw_text = call_ollama_api(prompt)
      end
      cleaned_text = clean_response_text(raw_text)
      parsed_data = JSON.parse(cleaned_text)

      # Validate the structure
      validate_actions_structure(parsed_data)

      parsed_data
    rescue JSON::ParserError => e
      Rails.logger.error "JSON parse error in action generation: #{e.message}"
      Rails.logger.error "Raw response: #{raw_text.inspect}" if defined?(raw_text)
      raise "Failed to parse actions response: #{e.message}"
    rescue => e
      Rails.logger.error "Error generating actions: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      raise
    end
  end

  private

  def build_prompt
    prompt_file = Rails.root.join("app", "services", "prompts", "capa_action_generation_prompt.txt")
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

    # Handle existing actions if any
    existing_actions = @capa.capa_actions.order(:created_at)
    if existing_actions.any?
      existing_actions_text = "Existing Corrective & Preventive Actions:\n"
      existing_actions.each_with_index do |action, index|
        existing_actions_text += "#{index + 1}. #{action.title} (#{action.action_type})\n"
        existing_actions_text += "   Status: #{action.status}\n"
        existing_actions_text += "   Notes: #{action.notes}\n" if action.notes.present?
      end
      existing_actions_text += "\n"

      prompt = prompt.gsub("{{EXISTING_ACTIONS}}", existing_actions_text)
    else
      # Remove existing actions section placeholder if no actions
      prompt = prompt.gsub("{{EXISTING_ACTIONS}}\n", "")
    end

    prompt
  end

  def call_openrouter_api(prompt)
    begin
      Rails.logger.info "Calling OpenRouter API for action generation"
      Rails.logger.info "Prompt length: #{prompt.length} chars"

      messages = [
        {
          role: "system",
          content: "You are an expert in quality management and corrective/preventive action planning. Always respond with valid JSON only, no markdown code blocks, no explanations."
        },
        {
          role: "user",
          content: prompt
        }
      ]

      response = @client.complete(
        messages,
        model: @model
      )

      if response.nil?
        Rails.logger.error "OpenRouter API returned nil response"
        raise "API returned nil response"
      end

      if response.is_a?(Hash) && response["error"]
        Rails.logger.error "API returned error: #{response['error'].inspect}"
        raise "API error: #{response['error']['message'] || response['error']}"
      end

      content = response.dig("choices", 0, "message", "content")

      if content.nil?
        Rails.logger.error "Failed to extract content from response"
        raise "Failed to extract content from API response"
      end

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
      Rails.logger.info "Calling Ollama API for action generation"
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

    # Language instruction based on current locale
    case I18n.locale.to_s
    when "ar"
      user_prompt += "IMPORTANT: Write all suggested corrective and preventive actions (titles, types, notes) in Arabic.\n\n"
    else
      user_prompt += "IMPORTANT: Write all suggested corrective and preventive actions (titles, types, notes) in English.\n\n"
    end

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

    # Handle existing actions if any
    existing_actions = @capa.capa_actions.order(:created_at)
    if existing_actions.any?
      user_prompt += "Existing Corrective & Preventive Actions:\n"
      existing_actions.each_with_index do |action, index|
        user_prompt += "#{index + 1}. #{action.title} (#{action.action_type})\n"
        user_prompt += "   Status: #{action.status}\n"
        user_prompt += "   Notes: #{action.notes}\n" if action.notes.present?
      end
      user_prompt += "\n"
    end

    user_prompt += "Generate the actions now:"
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

  def validate_actions_structure(data)
    unless data.is_a?(Hash) && data["actions"].is_a?(Array)
      raise "Response must contain an 'actions' array"
    end

    actions = data["actions"]

    unless actions.length == 5
      raise "Expected exactly 5 actions, got #{actions.length}"
    end

    actions.each_with_index do |action, index|
      unless action.is_a?(Hash)
        raise "Action #{index + 1} is not a valid object"
      end

      required_fields = %w[title action_type notes]
      missing_fields = required_fields - action.keys

      if missing_fields.any?
        raise "Action #{index + 1} is missing required fields: #{missing_fields.join(', ')}"
      end

      if action["title"].blank?
        raise "Action #{index + 1} has an empty title"
      end

      unless %w[corrective preventive].include?(action["action_type"])
        raise "Action #{index + 1} has invalid action_type: #{action['action_type']}. Must be 'corrective' or 'preventive'"
      end

      if action["notes"].blank?
        raise "Action #{index + 1} has empty notes"
      end
    end
  end
end
