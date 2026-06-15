class StructureDetectionService
  def initialize(ollama_client)
    @ollama_client = ollama_client
  end

  def detect_structure(chunk_text)
    prompt = build_structure_detection_prompt(chunk_text)
    response = @ollama_client.generate(prompt)
    save_response("stage1_structure_detection", response, prompt, chunk_text[0..200])

    cleaned = clean_json_response(response)
    parsed = JSON.parse(cleaned)

    if parsed.is_a?(Array)
      parsed = { "blocks" => parsed }
    end

    validate_structure_response(parsed)

    parsed
  rescue JSON::ParserError => e
    Rails.logger.error "Failed to parse structure detection response: #{e.message}"
    Rails.logger.error "Response: #{response[0..500]}" if defined?(response)
    save_response("stage1_structure_detection_ERROR", response, prompt, chunk_text[0..200]) if defined?(response) && defined?(prompt)
    { "blocks" => [] }
  rescue => e
    Rails.logger.error "Structure detection failed: #{e.class} - #{e.message}"
    Rails.logger.error "Response: #{response[0..500]}" if defined?(response)
    { "blocks" => [] }
  end

  private

  def build_structure_detection_prompt(chunk_text)
    chunk_text
  end

  def clean_json_response(response)
    cleaned = response.strip
    cleaned = cleaned.gsub(/^```json\s*/, "").gsub(/\s*```$/, "")
    cleaned = cleaned.gsub(/^```\s*/, "").gsub(/\s*```$/, "")

    if cleaned.include?("[")
      start_idx = cleaned.index("[")
      bracket_count = 0
      end_idx = start_idx

      cleaned[start_idx..-1].each_char.with_index do |char, idx|
        bracket_count += 1 if char == "["
        bracket_count -= 1 if char == "]"

        if bracket_count == 0
          end_idx = start_idx + idx
          break
        end
      end

      if bracket_count == 0 && end_idx > start_idx
        cleaned = cleaned[start_idx..end_idx]
      end
    elsif cleaned.include?("{")
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

  def validate_structure_response(parsed)
    unless parsed.is_a?(Hash) && parsed["blocks"].is_a?(Array)
      raise "Invalid structure response: expected { 'blocks': [...] }"
    end

    parsed["blocks"].each do |block|
      required_fields = [ "id", "raw_text" ]
      missing = required_fields - block.keys

      if missing.any?
        raise "Invalid block structure: missing fields #{missing.join(', ')}"
      end
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
      #{context ? "Context (first 200 chars):\n#{context}\n\n" : ""}
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
