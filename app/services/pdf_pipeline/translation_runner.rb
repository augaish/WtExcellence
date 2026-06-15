# frozen_string_literal: true

module PdfPipeline
  # Runs Stage 4: translate criterion/subcriterion names and checkpoint texts (en ↔ ar).
  class TranslationRunner
    def initialize(ollama_url:, debug_save: false, source_lang_hint: nil)
      @ollama_url = ollama_url || ENV.fetch("OLLAMA_URL", "http://localhost:11434")
      @debug_save = debug_save
      @source_lang_hint = source_lang_hint
    end

    def run(model)
      first_criterion = model.dig("model", "criteria", 0) || {}
      first_title_en = first_criterion["name_en"] || ""
      first_title_ar = first_criterion["name_ar"] || ""
      first_title = first_title_en.length > first_title_ar.length ? first_title_en : first_title_ar
      source_lang = if first_title.blank? && @source_lang_hint.present?
        @source_lang_hint
      else
        detect_language(first_title)
      end
      target_lang = source_lang == "en" ? "ar" : "en"

      Rails.logger.info "  Detected: #{source_lang == 'en' ? 'English' : 'Arabic'} → #{target_lang == 'en' ? 'English' : 'Arabic'}#{first_title.blank? && @source_lang_hint.present? ? ' (from standard hint)' : ''}"

      client = OllamaClient.new(model: "qwen-translator", base_url: @ollama_url)
      translation_map = build_translation_map(model, source_lang, target_lang)

      # KAQA (Arabic): if auto-detect assumed English→Arabic but content is in name_ar/text_ar, we get 0 texts. Use hint.
      if translation_map.empty? && @source_lang_hint.present? && @source_lang_hint != source_lang
        source_lang = @source_lang_hint
        target_lang = source_lang == "en" ? "ar" : "en"
        translation_map = build_translation_map(model, source_lang, target_lang)
        Rails.logger.info "  Using standard hint: #{source_lang == 'en' ? 'English' : 'Arabic'} → #{target_lang == 'en' ? 'English' : 'Arabic'} (#{translation_map.length} texts)"
      end

      Rails.logger.info "  Translating #{translation_map.length} texts..."

      chunk_size = 3
      chunks = translation_map.each_slice(chunk_size).to_a
      all_translations = []
      chunks.each_with_index do |chunk, chunk_idx|
        texts = chunk.map { |item| item[:text] }
        translations = batch_translate(client, texts, source_lang, target_lang, chunk_idx)
        if translations.size == texts.size && translations.any? { |t| t.present? }
          all_translations.concat(translations)
        else
          Rails.logger.warn "  Batch #{chunk_idx + 1}/#{chunks.size} failed or empty, falling back to one-by-one..."
          fallback = translate_one_by_one(client, texts, source_lang, target_lang)
          all_translations.concat(fallback)
        end
        sleep(0.3)
      end

      translation_map.each_with_index do |item, idx|
        path = item[:path]
        target = model["model"]
        path.each { |key| target = target[key] }
        target[item[:target_field]] = all_translations[idx] || ""
      end

      non_empty = all_translations.count { |t| t && !t.strip.empty? }
      Rails.logger.info "  Applied #{non_empty}/#{all_translations.length} translations"
      model
    end

    private

    def detect_language(text)
      text.match?(/[\u0600-\u06FF]/) ? "ar" : "en"
    end

    # Only add items that need translation: source present and target blank (skip when both en and ar already present).
    def build_translation_map(model, source_lang, target_lang)
      source_suffix = source_lang
      target_suffix = target_lang
      map = []

      model["model"]["criteria"].each_with_index do |criterion, c_idx|
        sf = "name_#{source_suffix}"
        tf = "name_#{target_suffix}"
        map << { path: ["criteria", c_idx], text: criterion[sf], source_field: sf, target_field: tf } if criterion[sf].present? && criterion[tf].blank?

        (criterion["subcriteria"] || []).each_with_index do |sub, s_idx|
          map << { path: ["criteria", c_idx, "subcriteria", s_idx], text: sub[sf], source_field: sf, target_field: tf } if sub[sf].present? && sub[tf].blank?

          (sub["subcriteria"] || []).each_with_index do |nested, n_idx|
            map << { path: ["criteria", c_idx, "subcriteria", s_idx, "subcriteria", n_idx], text: nested[sf], source_field: sf, target_field: tf } if nested[sf].present? && nested[tf].blank?
            cs = "text_#{source_suffix}"
            ct = "text_#{target_suffix}"
            (nested["checkpoints"] || []).each_with_index do |cp, cp_idx|
              map << { path: ["criteria", c_idx, "subcriteria", s_idx, "subcriteria", n_idx, "checkpoints", cp_idx], text: cp[cs], source_field: cs, target_field: ct } if cp[cs].present? && cp[ct].blank?
            end
          end

          cs = "text_#{source_suffix}"
          ct = "text_#{target_suffix}"
          (sub["checkpoints"] || []).each_with_index do |cp, cp_idx|
            map << { path: ["criteria", c_idx, "subcriteria", s_idx, "checkpoints", cp_idx], text: cp[cs], source_field: cs, target_field: ct } if cp[cs].present? && cp[ct].blank?
          end
        end
      end
      map
    end

    def batch_translate(client, texts, source_lang, target_lang, chunk_idx = 0)
      return [] if texts.empty?

      source_name = source_lang == "en" ? "English" : "Arabic"
      target_name = target_lang == "en" ? "English" : "Arabic"
      input_json = JSON.generate(texts)
      max_retries = 2
      retries = 0
      response = nil
      cleaned = nil

      while retries <= max_retries
        prompt = build_translation_prompt(texts, source_name, target_name, input_json, retries)
        begin
          response = client.generate(prompt)
          cleaned = response.strip
            .gsub(/^```json\s*/i, "")
            .gsub(/^```\s*/, "")
            .gsub(/```\s*$/, "")
            .strip
          translations = JSON.parse(cleaned)
          translations = [translations].flatten unless translations.is_a?(Array)
          if translations.length != texts.length
            Rails.logger.warn "  Expected #{texts.length} translations, got #{translations.length}"
            translations << "" while translations.length < texts.length
            translations = translations.take(texts.length)
          end
          return translations
        rescue JSON::ParserError, StandardError => e
          if retries < max_retries
            retries += 1
            Rails.logger.warn "  Translation/parse failed (attempt #{retries}/#{max_retries + 1}): #{e.message}. Retrying with stricter prompt..."
            sleep(1)
          else
            Rails.logger.error "  Translation batch failed after #{max_retries + 1} attempts: #{e.message}"
            save_failed(texts, prompt, response, cleaned, e, source_lang, target_lang) if @debug_save
            return texts.map { "" }
          end
        end
      end

      texts.map { "" }
    end

    def build_translation_prompt(texts, source_name, target_name, input_json, retry_attempt)
      if retry_attempt.zero?
        <<~PROMPT
          Translate the following JSON array of texts from #{source_name} to #{target_name}.

          INPUT:
          #{input_json}

          OUTPUT FORMAT:
          Return a JSON array of translations in the same order. No explanations, just the JSON array.
        PROMPT
      else
        <<~PROMPT
          Translate the following JSON array of texts from #{source_name} to #{target_name}.

          CRITICAL: Your previous response was not valid JSON. You must return ONLY a valid JSON array of exactly #{texts.length} strings. No markdown code blocks, no explanation, no text before or after the array. Each array element is the translation of the corresponding input string.

          INPUT:
          #{input_json}

          Return ONLY the JSON array, e.g. ["first translation", "second translation"].
        PROMPT
      end
    end

    def translate_one_by_one(client, texts, source_lang, target_lang)
      results = []
      texts.each_with_index do |text, i|
        single = batch_translate(client, [text], source_lang, target_lang, 0)
        results << (single[0] || "")
        sleep(0.2)
      end
      results
    end

    def save_failed(texts, prompt, response, cleaned, error, source_lang, target_lang)
      timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
      filename = "FAILED_translation_#{source_lang}_to_#{target_lang}_#{texts.length}_#{timestamp}.txt"
      filepath = Rails.root.join("tmp", "ollama_responses", "translation", "failed", filename)
      FileUtils.mkdir_p(filepath.dirname)
      json_detail = error.is_a?(JSON::ParserError) ? "\nJSON Error: #{error.message}" : ""
      content = <<~CONTENT
        FAILED TRANSLATION REQUEST
        Timestamp: #{Time.current.iso8601}
        Error: #{error.class} - #{error.message}#{json_detail}
        Response length: #{response&.length || 0}
        INPUT TEXTS:
        #{JSON.pretty_generate(texts)}
        PROMPT:
        #{prompt}
        RAW RESPONSE:
        #{response || '(none)'}
        CLEANED:
        #{cleaned || '(none)'}
      CONTENT
      File.write(filepath, content)
      Rails.logger.info "  Debug: saved failed translation to #{filepath}"
    rescue => e
      Rails.logger.warn "  Could not save failed translation: #{e.message}"
    end
  end
end
