class TranslationService
  def initialize(ollama_client)
    @ollama_client = ollama_client
  end

  def translate(extracted_content)
    prompt = build_translation_prompt(extracted_content)
    response = @ollama_client.generate(prompt)
    save_response("stage3_translation", response, prompt, "Block ID: #{extracted_content['id']}")

    cleaned = clean_json_response(response)
    translated_content = JSON.parse(cleaned)
    validate_translation_response(translated_content, extracted_content["id"])

    translated_content
  rescue JSON::ParserError => e
    Rails.logger.error "Failed to parse translation response for block #{extracted_content['id']}: #{e.message}"
    Rails.logger.error "Response: #{response[0..500]}" if defined?(response)
    save_response("stage3_translation_ERROR", response, prompt, "Block ID: #{extracted_content['id']}") if defined?(response) && defined?(prompt)
    {
      "id" => extracted_content["id"],
      "name_en" => extracted_content["name"] || "[Translation failed]",
      "name_ar" => "[فشل الترجمة]",
      "text_en" => extracted_content["text"] || "[Translation failed]",
      "text_ar" => "[فشل الترجمة]"
    }
  rescue => e
    Rails.logger.error "Translation failed for block #{extracted_content['id']}: #{e.class} - #{e.message}"
    {
      "id" => extracted_content["id"],
      "name_en" => extracted_content["name"] || "[Translation failed]",
      "name_ar" => "[فشل الترجمة]",
      "text_en" => extracted_content["text"] || "[Translation failed]",
      "text_ar" => "[فشل الترجمة]"
    }
  end

  private

  def build_translation_system_prompt
    <<~SYSTEM
      You are a professional technical translator specializing in quality management standards.

      Your task is to translate cleaned clause content into bilingual output (English and Arabic).

      You must return ONLY valid JSON with: id, name_en, name_ar, text_en, and text_ar fields. Translate name and text fields independently. Never leave language fields empty unless text is truly unreadable.
    SYSTEM
  end

  def build_translation_prompt(extracted_content)
    <<~PROMPT
      You are a professional technical translator specializing in quality management standards.

      You will receive cleaned clause content in ONE language (Arabic or English).

      TASK:

      1. Detect the source language.

      2. Produce FULL bilingual output:

         - If source is English → translate to Arabic

         - If source is Arabic → translate to English

         - If mixed → ensure both languages are complete

      3. Preserve technical meaning exactly.

      4. Maintain Arabic RTL order and correct terminology.

      5. If text contains "[corrupted]", keep it as-is and do NOT guess.

      RULES:

      - NEVER leave a language field empty.

      - Only use "[Translation needed]" if text is unreadable.

      - Do NOT alter clause IDs.

      - Do NOT summarize.

      OUTPUT:

      Return ONLY valid JSON.

      SCHEMA:

      {
        "id": "string",
        "name_en": "string",
        "name_ar": "string",
        "text_en": "string",
        "text_ar": "string"
      }

      EXTRACTED CONTENT:
      ID: #{extracted_content["id"]}
      Name: #{extracted_content["name"]}
      Text: #{extracted_content["text"]}
    PROMPT
  end

  def clean_json_response(response)
    cleaned = response.strip
    cleaned = cleaned.gsub(/^```json\s*/, "").gsub(/\s*```$/, "")
    cleaned = cleaned.gsub(/^```\s*/, "").gsub(/\s*```$/, "")

    if cleaned.include?("{")
      start_idx = cleaned.index("{")
      brace_count = 0
      end_idx = start_idx

      cleaned[start_idx..-1].each_char.with_index do |char, idx|
        brace_count += 1 if char == "{"
        brace_count -= 1 if char == "}"

        if brace_count == 0
          end_idx = start_idx + idx
          break
        end
      end

      if brace_count == 0 && end_idx > start_idx
        cleaned = cleaned[start_idx..end_idx]
      end
    end

    cleaned = cleaned.gsub(/[\x00-\x1F\x7F]/, "")
    cleaned
  end

  def validate_translation_response(parsed, expected_id)
    unless parsed.is_a?(Hash)
      raise "Invalid translation response: expected Hash"
    end

    unless parsed["id"] == expected_id
      Rails.logger.warn "ID mismatch in translation: expected #{expected_id}, got #{parsed['id']}"
    end

    required_fields = [ "id", "name_en", "name_ar", "text_en", "text_ar" ]
    missing = required_fields - parsed.keys

    if missing.any?
      raise "Invalid translation response: missing fields #{missing.join(', ')}"
    end
  end

  def save_response(stage_name, response, prompt, context = nil)
    timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
    filename = "#{stage_name}_#{timestamp}.txt"
    filepath = Rails.root.join("tmp", "ollama_responses", filename)

    FileUtils.mkdir_p(Rails.root.join("tmp", "ollama_responses"))

    metadata = <<~METADATA
      ============================================
      OLLAMA RESPONSE - #{stage_name.upcase}
      ============================================
      Timestamp: #{Time.current.iso8601}
      Stage: #{stage_name}
      Prompt length: #{prompt.length} characters
      Response length: #{response.length} characters
      ============================================
      #{context ? "Context:\n#{context}\n\n" : ""}
      PROMPT:
      #{prompt}

      ============================================
      RESPONSE:
      ============================================
    METADATA

    File.write(filepath, metadata + response)
    Rails.logger.info "✅ Saved #{stage_name} response to: #{filepath}"
  rescue => e
    Rails.logger.warn "Could not save response: #{e.message}"
  end
end
