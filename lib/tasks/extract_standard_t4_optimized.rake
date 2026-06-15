namespace :pdf do
  desc "T4-optimized standard extraction (14B models, 8K context)"
  task extract_standard_t4: :environment do
    pdf_path = ENV["PDF_PATH"]
    standard_type = ENV["STANDARD"] || "EFQM"

    # Special mode: ASSEMBLE_ONLY - skip extraction, just assemble from latest cache
    if ENV["ASSEMBLE_ONLY"] == "true"
      puts "\n" + "="*70
      puts "ASSEMBLE ONLY MODE"
      puts "="*70
      puts "Standard: #{standard_type}"
      puts "Loading latest cached files and assembling..."
      puts "="*70 + "\n"

      existing_structure = load_stage_progress("structure")
      existing_checkpoints = load_stage_progress("checkpoints")

      unless existing_structure && existing_checkpoints
        puts "❌ Error: Cannot find cached structure or checkpoint files"
        puts "   Required files:"
        puts "   - tmp/ollama_responses/t4_optimized/progress_structure_*.json"
        puts "   - tmp/ollama_responses/t4_optimized/progress_checkpoints_*.json"
        puts ""
        puts "   Run a full extraction first, then use ASSEMBLE_ONLY=true"
        exit 1
      end

      all_blocks = existing_structure
      all_checkpoints = existing_checkpoints

      puts "✓ Loaded structure: #{all_blocks.length} blocks"
      puts "✓ Loaded checkpoints: #{all_checkpoints.length} checkpoints"

      # Show summary
      criteria = all_blocks.select { |b| b["level"] == "criterion" }
      subcriteria = all_blocks.select { |b| b["level"] == "subcriterion" }
      nested_subcriteria = all_blocks.select { |b| b["level"] == "nested_subcriterion" }
      puts "  - #{criteria.length} criteria"
      puts "  - #{subcriteria.length} subcriteria"
      puts "  - #{nested_subcriteria.length} nested subcriteria"

      # Skip to assembly (goto label simulation)
      skip_to_assembly = true
    else
      skip_to_assembly = false
    end

    unless skip_to_assembly || (pdf_path && File.exist?(pdf_path))
      puts "❌ Please provide PDF_PATH environment variable"
      puts "Usage: rake pdf:extract_standard_t4 PDF_PATH=/path/to/pdf.pdf STANDARD=EFQM"
      puts ""
      puts "Options:"
      puts "  SKIP_CACHE=true    - Force re-run all stages (ignore cached progress)"
      puts "  STANDARD=EFQM      - Specify standard type (EFQM, KAQA, ISO9001)"
      puts "  TRANSLATE=false    - Skip translation stage (default: translate)"
      puts "  ASSEMBLE_ONLY=true - Skip extraction, assemble from latest cached files"
      puts ""
      puts "Stages:"
      puts "  1. Structure extraction (criteria + subcriteria)"
      puts "  2. Checkpoint extraction (per subcriterion)"
      puts "  3. Assembly (code-based)"
      puts "  4. Translation (EN→AR or AR→EN, auto-detected)"
      puts ""
      puts "Caching:"
      puts "  - If both Stage 1 & 2 are cached, skips directly to Stage 3 (Assembly)"
      puts "  - If only one stage is cached, prompts for that stage individually"
      puts "  - Each stage can be cached and skipped independently"
      puts "  - Progress files: tmp/ollama_responses/t4_optimized/progress_*.json"
      exit 1
    end

    unless skip_to_assembly
      puts "\n" + "="*70
      puts "T4-OPTIMIZED STANDARD EXTRACTION + TRANSLATION"
      puts "="*70
      puts "PDF: #{pdf_path}"
      puts "Standard: #{standard_type}"
      puts "Models:"
      puts "  - qwen-extract-structure (Stage 1: Structure)"
      puts "  - qwen-extract-checkpoints (Stage 2: Checkpoints)"
      puts "  - qwen-translator (Stage 4: Translation)"
      puts "Stages: Structure → Checkpoints → Assembly → Translation"
      puts "="*70 + "\n"

      # Stage 0: Extract text
      puts "Stage 0: Extracting text from PDF..."
      full_text = extract_text_with_tika(pdf_path)
      puts "  ✓ Extracted #{full_text.length} characters"

      # Stage 0.5: Clean text
      puts "\nStage 0.5: Cleaning text..."
      cleaned_text = clean_text(full_text)
      puts "  ✓ Cleaned to #{cleaned_text.length} characters"

      # Stage 0.75: Split into pages (approx)
      puts "\nStage 0.75: Splitting into pages..."
      page_texts = split_into_pages(cleaned_text)
      puts "  ✓ Split into #{page_texts.length} approximate pages"

      # Check for existing progress for BOTH stages
      existing_structure = load_stage_progress("structure")
      existing_checkpoints = load_stage_progress("checkpoints")

    # If BOTH stages are cached, offer to skip directly to assembly
    if existing_structure && existing_checkpoints
      skip_both = ENV["SKIP_CACHE"] != "true"  # Default: use cache unless SKIP_CACHE=true

      puts "\n⚡ Found cached data for BOTH stages:"
      puts "   - Structure: #{existing_structure.length} blocks"
      puts "   - Checkpoints: #{existing_checkpoints.length} checkpoints"

      if skip_both
        puts "\n   Skip to Stage 3 (Assembly)? (y/n) [default: y, or set SKIP_CACHE=true to force re-run]"
        print "   > "
        response = STDIN.gets.chomp.downcase
        skip_both = response.empty? || response == "y" || response == "yes"
      end

      if skip_both
        all_blocks = existing_structure
        all_checkpoints = existing_checkpoints
        puts "   ✓ Skipping to Stage 3 (Assembly) with cached data"

        # Show summary
        criteria = all_blocks.select { |b| b["level"] == "criterion" }
        subcriteria = all_blocks.select { |b| b["level"] == "subcriterion" }
        nested_subcriteria = all_blocks.select { |b| b["level"] == "nested_subcriterion" }
        puts "    - #{criteria.length} criteria"
        puts "    - #{subcriteria.length} subcriteria"
        puts "    - #{nested_subcriteria.length} nested subcriteria"
      else
        puts "\n   Re-running both stages..."
        # Fall through to normal execution
        existing_structure = nil
        existing_checkpoints = nil
      end
    end

    # Stage 1: Extract structure (or use cache)
    if !all_blocks  # Only run if not already loaded from cache
      if existing_structure
        skip_cached = ENV["SKIP_CACHE"] != "true"

        puts "\n⚡ Found existing structure file (#{existing_structure.length} blocks)"

        if skip_cached
          puts "   Skip Stage 1? (y/n) [default: y, or set SKIP_CACHE=true to force re-run]"
          print "   > "
          response = STDIN.gets.chomp.downcase
          skip_cached = response.empty? || response == "y" || response == "yes"
        end

        if skip_cached
          all_blocks = existing_structure
          puts "   ✓ Skipped Stage 1, using cached structure"
        else
          puts "\n   Re-running Stage 1..."
          all_blocks = run_stage1_structure_extraction(page_texts, standard_type)
          puts "  ✓ Extracted #{all_blocks.length} structural blocks"
          save_stage_progress("structure", all_blocks)
        end
      else
        puts "\nStage 1: Extracting structure (criteria + subcriteria)..."
        all_blocks = run_stage1_structure_extraction(page_texts, standard_type)
        puts "  ✓ Extracted #{all_blocks.length} structural blocks"
        save_stage_progress("structure", all_blocks)
      end

      # Show structure summary
      criteria = all_blocks.select { |b| b["level"] == "criterion" }
      subcriteria = all_blocks.select { |b| b["level"] == "subcriterion" }
      nested_subcriteria = all_blocks.select { |b| b["level"] == "nested_subcriterion" }
      puts "    - #{criteria.length} criteria"
      puts "    - #{subcriteria.length} subcriteria"
      puts "    - #{nested_subcriteria.length} nested subcriteria"
    end

      # Stage 2: Extract checkpoints (or use cache)
      if !all_checkpoints  # Only run if not already loaded from cache
        if existing_checkpoints
          skip_cached = ENV["SKIP_CACHE"] != "true"

          puts "\n⚡ Found existing checkpoints file (#{existing_checkpoints.length} checkpoints)"

          if skip_cached
            puts "   Skip Stage 2? (y/n) [default: y, or set SKIP_CACHE=true to force re-run]"
            print "   > "
            response = STDIN.gets.chomp.downcase
            skip_cached = response.empty? || response == "y" || response == "yes"
          end

          if skip_cached
            all_checkpoints = existing_checkpoints
            puts "   ✓ Skipped Stage 2, using cached checkpoints"
          else
            puts "\n   Re-running Stage 2..."
            target_subcriteria = find_deepest_subcriteria(all_blocks)
            puts "  Processing #{target_subcriteria.length} subcriteria for checkpoints..."
            all_checkpoints = run_stage2_checkpoint_extraction(target_subcriteria, page_texts, standard_type)
            puts "  ✓ Extracted #{all_checkpoints.length} total checkpoints"
            save_stage_progress("checkpoints", all_checkpoints)
          end
        else
          puts "\nStage 2: Extracting checkpoints (T4-safe: one at a time)..."
          target_subcriteria = find_deepest_subcriteria(all_blocks)
          puts "  Processing #{target_subcriteria.length} subcriteria for checkpoints..."
          all_checkpoints = run_stage2_checkpoint_extraction(target_subcriteria, page_texts, standard_type)
          puts "  ✓ Extracted #{all_checkpoints.length} total checkpoints"
          save_stage_progress("checkpoints", all_checkpoints)
        end
      end
    end  # End of unless skip_to_assembly

    # Stage 3: Assemble (code-based, no LLM)
    puts "\nStage 3: Assembling final model (code-based)..."

    # Combine blocks and checkpoints into single array (assemble_model expects one array)
    combined_blocks = all_blocks.dup
    all_checkpoints.each do |checkpoint|
      checkpoint["level"] = "checkpoint" unless checkpoint["level"]
      combined_blocks << checkpoint
    end

    final_model = assemble_model(combined_blocks)
    puts "  ✓ Assembly complete"

    # Stage 4: Translation (optional, based on TRANSLATE env variable)
    if ENV["TRANSLATE"] != "false"  # Default: translate (set TRANSLATE=false to skip)
      puts "\nStage 4: Translation..."

      # Check for existing translation
      existing_translation = load_stage_progress("translation")

      if existing_translation
        skip_cached = ENV["SKIP_CACHE"] != "true"

        puts "  ⚡ Found existing translation"

        if skip_cached
          puts "   Skip Stage 4? (y/n) [default: y, or set SKIP_CACHE=true to force re-run]"
          print "   > "
          response = STDIN.gets.chomp.downcase
          skip_cached = response.empty? || response == "y" || response == "yes"
        end

        if skip_cached
          final_model = existing_translation
          puts "   ✓ Skipped Stage 4, using cached translation"
        else
          puts "\n   Re-running Stage 4..."
          final_model = run_stage4_translation(final_model, standard_type)
          puts "  ✓ Translation complete"
          save_stage_progress("translation", final_model)
        end
      else
        final_model = run_stage4_translation(final_model, standard_type)
        puts "  ✓ Translation complete"
        save_stage_progress("translation", final_model)
      end
    else
      puts "\n⏭️  Skipping Stage 4 (Translation) - TRANSLATE=false"
    end

    # Save final output
    timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
    output_path = Rails.root.join(
      "tmp", "ollama_responses", "t4_optimized",
      "standard_t4_#{standard_type.downcase}_#{timestamp}.json"
    )
    FileUtils.mkdir_p(output_path.dirname)
    File.write(output_path, JSON.pretty_generate(final_model))

    puts "\n" + "="*70
    puts "✅ EXTRACTION COMPLETE"
    puts "="*70
    puts "Output: #{output_path}"
    puts "Criteria: #{final_model['model']['criteria'].length}"
    total_subcriteria = final_model["model"]["criteria"].sum { |c| c["subcriteria"]&.length || 0 }
    puts "Subcriteria: #{total_subcriteria}"

    # Count checkpoints and translations (check both AR and EN)
    total_checkpoints = 0
    translated_checkpoints = 0
    final_model["model"]["criteria"].each do |criterion|
      (criterion["subcriteria"] || []).each do |sub|
        (sub["checkpoints"] || []).each do |cp|
          total_checkpoints += 1
          # Check both ar and en translations
          translated = (cp["text_ar"] && !cp["text_ar"].empty?) || (cp["text_en"] && !cp["text_en"].empty?)
          translated_checkpoints += 1 if translated
        end
        (sub["subcriteria"] || []).each do |nested|
          (nested["checkpoints"] || []).each do |cp|
            total_checkpoints += 1
            translated = (cp["text_ar"] && !cp["text_ar"].empty?) || (cp["text_en"] && !cp["text_en"].empty?)
            translated_checkpoints += 1 if translated
          end
        end
      end
    end

    if total_checkpoints > 0 && ENV["TRANSLATE"] != "false"
      puts "Checkpoints: #{total_checkpoints} (#{translated_checkpoints} with translations)"
    elsif total_checkpoints > 0
      puts "Checkpoints: #{total_checkpoints}"
    end
    puts "="*70 + "\n"
  end

  def extract_text_with_tika(pdf_path)
    require "open3"
    stdout, stderr, status = Open3.capture3("tika", "--text", pdf_path)

    unless status.success?
      raise "Tika extraction failed: #{stderr}"
    end

    stdout
  end

  def clean_text(text)
    text
      .gsub(/\r\n/, "\n")
      .gsub(/\r/, "\n")
      .gsub(/\n{3,}/, "\n\n")
      .gsub(/ {2,}/, " ")
      .gsub(/[^\p{Arabic}\p{Latin}\p{N}\p{P}\s\-•▪◦○●]/, "")
      .strip
  end

  def split_into_pages(text, chars_per_page: 2500)
    pages = []
    current_pos = 0

    while current_pos < text.length
      chunk_end = [ current_pos + chars_per_page, text.length ].min

      if chunk_end < text.length
        newline_pos = text.rindex("\n", chunk_end)
        chunk_end = newline_pos if newline_pos && newline_pos > current_pos
      end

      pages << text[current_pos...chunk_end].strip
      current_pos = chunk_end
    end

    pages.reject(&:empty?)
  end

  def run_stage1_structure_extraction(page_texts, standard_type)
    ollama_url = ENV.fetch("OLLAMA_URL", "http://localhost:11434")
    client = OllamaClient.new(
      model: "qwen-extract-structure",
      base_url: ollama_url
    )

    all_blocks = []

    # Process in optimal chunks: 3-4 pages with 750 char overlap (10K context)
    page_texts.each_slice(3).with_index do |page_group, idx|
      chunk_num = idx + 1
      total_chunks = (page_texts.length.to_f / 3).ceil

      puts "  Processing chunk #{chunk_num}/#{total_chunks}..."

      # Build chunk with overlap
      chunk_text = page_group.join("\n\n")

      # Add overlap from next page if exists
      next_page_idx = (idx + 1) * 3
      if next_page_idx < page_texts.length
        overlap = page_texts[next_page_idx][0..750]
        chunk_text += "\n\n" + overlap
      end

      prompt = build_structure_extraction_prompt(chunk_text, standard_type)

      max_retries = 2
      retries = 0

      cleaned = nil
      begin
        response = client.generate(prompt)

        # ALWAYS save raw response for debugging
        save_raw_response("stage1_structure", "chunk_#{chunk_num}", response, prompt)

        # Minimal cleaning: remove markdown code blocks only
        cleaned = response.strip
        cleaned = cleaned.gsub(/^```json\s*/i, "")
        cleaned = cleaned.gsub(/^```\s*/, "")
        cleaned = cleaned.gsub(/```\s*$/, "")
        cleaned = cleaned.strip

        # Try to parse
        parsed = JSON.parse(cleaned)

        # Save the cleaned response
        save_cleaned_response("stage1_structure", "chunk_#{chunk_num}", cleaned)

        blocks = parsed["blocks"] || []
        puts "    Found #{blocks.length} blocks"
        all_blocks.concat(blocks)

      rescue JSON::ParserError => e
        if retries < max_retries
          retries += 1
          puts "    JSON parse failed, retry #{retries}/#{max_retries}..."
          puts "    Error: #{e.message}"
          sleep(1)
          retry
        else
          puts "    ⚠️  JSON parse error after #{max_retries} retries: #{e.message}"
          save_failed_response("stage1_structure", "chunk_#{chunk_num}", response, cleaned, e.message)
        end
      rescue => e
        puts "    ⚠️  Error: #{e.message}"
        save_failed_response("stage1_structure", "chunk_#{chunk_num}", response, cleaned, e.message)
      end

      sleep(0.2)
    end

    # Deduplicate (keep first occurrence)
    deduplicate_blocks(all_blocks)
  end

  def build_structure_extraction_prompt(chunk_text, standard_type)
    # Keep prompt minimal - system prompt is in Modelfile
    <<~PROMPT
      Standard type: #{standard_type}

      Extract ONLY criteria and subcriteria that have explicit IDs/numbers in the text.

      RULES:
      - ONLY extract items with explicit numeric IDs (e.g., "Criterion 1", "1.1", "1a", etc.)
      - DO NOT invent IDs for bullet points or descriptive text
      - DO NOT create structure from unnumbered lists
      - If a criterion has no numbered subcriteria in the text, extract ONLY the criterion

      For each item found, extract:
      - id: The EXACT ID from the document (e.g., "1", "1.1", "1a")
      - level: "criterion" or "subcriterion" or "nested_subcriterion"
      - parent_id: The ID of the parent (null for top-level criteria)
      - raw_text: The full text of that section

      TEXT:
      #{chunk_text}

      Return JSON with "blocks" array. Each block must have: id, level, parent_id, raw_text.
    PROMPT
  end

  def run_stage2_checkpoint_extraction(target_subcriteria, page_texts, standard_type)
    ollama_url = ENV.fetch("OLLAMA_URL", "http://localhost:11434")
    client = OllamaClient.new(
      model: "qwen-extract-checkpoints",
      base_url: ollama_url
    )

    all_checkpoints = []

    target_subcriteria.each_with_index do |subcriterion, idx|
      sub_id = subcriterion["id"]
      puts "    Processing #{sub_id} (#{idx + 1}/#{target_subcriteria.length})..."

      # Find relevant pages containing this subcriterion
      relevant_text = find_relevant_pages_for_subcriterion(
        sub_id,
        subcriterion["raw_text"],
        page_texts
      )

      prompt = build_checkpoint_extraction_prompt(sub_id, relevant_text)

      max_retries = 2
      retries = 0

      cleaned = nil
      begin
        response = client.generate(prompt)

        # ALWAYS save raw response for debugging
        save_raw_response("stage2_checkpoints", sub_id.gsub(".", "_"), response, prompt)

        # Minimal cleaning: remove markdown code blocks only
        cleaned = response.strip
        cleaned = cleaned.gsub(/^```json\s*/i, "")
        cleaned = cleaned.gsub(/^```\s*/, "")
        cleaned = cleaned.gsub(/```\s*$/, "")
        cleaned = cleaned.strip

        # Try to parse
        parsed = JSON.parse(cleaned)

        # Save the cleaned response
        save_cleaned_response("stage2_checkpoints", sub_id.gsub(".", "_"), cleaned)

        checkpoints = parsed["checkpoints"] || []
        puts "      Found #{checkpoints.length} checkpoints"
        all_checkpoints.concat(checkpoints)

      rescue JSON::ParserError => e
        if retries < max_retries
          retries += 1
          puts "      JSON parse failed, retry #{retries}/#{max_retries}..."
          puts "      Error: #{e.message}"
          sleep(1)
          retry
        else
          puts "      ⚠️  JSON parse error: #{e.message}"
          save_failed_response("stage2_checkpoints", sub_id.gsub(".", "_"), response, cleaned, e.message)
        end
      rescue => e
        puts "      ⚠️  Error: #{e.message}"
        save_failed_response("stage2_checkpoints", sub_id.gsub(".", "_"), response, cleaned, e.message)
      end

      sleep(0.2)
    end

    deduplicate_blocks(all_checkpoints)
  end

  # ============================================================================
  # STAGE 4: TRANSLATION
  # ============================================================================

  def run_stage4_translation(model, standard_type)
    # Auto-detect source language from first criterion title
    # Check both name_en and name_ar to find which one has content
    first_criterion = model.dig("model", "criteria", 0) || {}
    first_title_en = first_criterion["name_en"] || ""
    first_title_ar = first_criterion["name_ar"] || ""

    # Use whichever field has content
    first_title = first_title_en.length > first_title_ar.length ? first_title_en : first_title_ar
    source_lang = detect_language(first_title)
    target_lang = source_lang == "en" ? "ar" : "en"

    puts "  Detected source language: #{source_lang == 'en' ? 'English' : 'Arabic'}"
    puts "  Target language: #{target_lang == 'en' ? 'English' : 'Arabic'}"

    client = OllamaClient.new(model: "qwen-translator")

    # Step 1: Collect all texts that need translation
    puts "  Collecting texts to translate..."
    translation_map = []  # Array of { path:, text:, source_field:, target_field: }

    # Determine field names based on source/target language
    # assemble_model uses: name_en/name_ar for criteria/subcriteria, text_en/text_ar for checkpoints
    source_suffix = source_lang
    target_suffix = target_lang

    model["model"]["criteria"].each_with_index do |criterion, c_idx|
      # Criterion
      source_field = "name_#{source_suffix}"
      target_field = "name_#{target_suffix}"
      if criterion[source_field] && !criterion[source_field].empty?
        translation_map << {
          path: [ "criteria", c_idx ],
          text: criterion[source_field],
          source_field: source_field,
          target_field: target_field
        }
      end

      # Subcriteria
      (criterion["subcriteria"] || []).each_with_index do |sub, s_idx|
        if sub[source_field] && !sub[source_field].empty?
          translation_map << {
            path: [ "criteria", c_idx, "subcriteria", s_idx ],
            text: sub[source_field],
            source_field: source_field,
            target_field: target_field
          }
        end

        # Nested subcriteria
        (sub["subcriteria"] || []).each_with_index do |nested, n_idx|
          if nested[source_field] && !nested[source_field].empty?
            translation_map << {
              path: [ "criteria", c_idx, "subcriteria", s_idx, "subcriteria", n_idx ],
              text: nested[source_field],
              source_field: source_field,
              target_field: target_field
            }
          end

          # Checkpoints in nested subcriteria (use text_* not name_*)
          checkpoint_source = "text_#{source_suffix}"
          checkpoint_target = "text_#{target_suffix}"
          (nested["checkpoints"] || []).each_with_index do |checkpoint, cp_idx|
            if checkpoint[checkpoint_source] && !checkpoint[checkpoint_source].empty?
              translation_map << {
                path: [ "criteria", c_idx, "subcriteria", s_idx, "subcriteria", n_idx, "checkpoints", cp_idx ],
                text: checkpoint[checkpoint_source],
                source_field: checkpoint_source,
                target_field: checkpoint_target
              }
            end
          end
        end

        # Checkpoints in subcriteria
        checkpoint_source = "text_#{source_suffix}"
        checkpoint_target = "text_#{target_suffix}"
        (sub["checkpoints"] || []).each_with_index do |checkpoint, cp_idx|
          if checkpoint[checkpoint_source] && !checkpoint[checkpoint_source].empty?
            translation_map << {
              path: [ "criteria", c_idx, "subcriteria", s_idx, "checkpoints", cp_idx ],
              text: checkpoint[checkpoint_source],
              source_field: checkpoint_source,
              target_field: checkpoint_target
            }
          end
        end
      end
    end

    puts "  Total texts to translate: #{translation_map.length}"

    # Show preview of first few texts
    if translation_map.length > 0
      puts "  Preview of first 3 texts:"
      translation_map.take(3).each_with_index do |item, idx|
        preview = item[:text].length > 60 ? "#{item[:text][0..60]}..." : item[:text]
        puts "    #{idx + 1}. [#{item[:source_field]}] #{preview}"
      end
    end

    # Step 2: Batch translate in chunks
    chunk_size = 10  # Translate 10 texts per API call (smaller batches for better reliability)
    chunks = translation_map.each_slice(chunk_size).to_a

    puts "  Translating in #{chunks.length} batches (~#{chunk_size} texts per batch)..."

    all_translations = []
    chunks.each_with_index do |chunk, chunk_idx|
      puts "    Batch #{chunk_idx + 1}/#{chunks.length} (#{chunk.length} texts)..."

      translations = batch_translate(client, chunk.map { |item| item[:text] }, source_lang, target_lang, chunk_idx)
      all_translations.concat(translations)

      puts "      ✓ Received #{translations.length} translations"

      sleep(0.3)  # Small delay between batches
    end

    # Step 3: Map translations back to model
    puts "  Applying translations to model..."
    translation_map.each_with_index do |item, idx|
      translated_text = all_translations[idx] || ""

      # Navigate to the correct location in the model
      path = item[:path]
      target = model["model"]

      # Navigate to the target object
      path.each do |key|
        target = target[key]
      end

      # Set translated field using target_field from the map
      target[item[:target_field]] = translated_text
    end

    # Verify translations
    non_empty_count = all_translations.count { |t| t && !t.strip.empty? }
    puts "  ✓ Applied #{non_empty_count}/#{all_translations.length} translations"

    if non_empty_count < all_translations.length
      puts "  ⚠️  Warning: #{all_translations.length - non_empty_count} translations are empty"
    end

    model
  end

  def detect_language(text)
    # Simple heuristic: check for Arabic characters
    text.match?(/[\u0600-\u06FF]/) ? "ar" : "en"
  end

  def batch_translate(client, texts, source_lang, target_lang, batch_idx = 0)
    return [] if texts.empty?

    source_name = source_lang == "en" ? "English" : "Arabic"
    target_name = target_lang == "en" ? "English" : "Arabic"

    # Build comma-separated input
    input_text = texts.join(",")

    prompt = <<~PROMPT
      Translate the following comma-separated texts from #{source_name} to #{target_name}.

      INPUT:
      #{input_text}

      OUTPUT FORMAT:
      Return comma-separated translations in the same order. No explanations, just the translations.
    PROMPT

    max_retries = 2
    retries = 0

    begin
      response = client.generate(prompt)

      # Save raw response for debugging
      timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
      raw_path = Rails.root.join("tmp", "ollama_responses", "t4_optimized", "raw", "raw_translation_batch_#{batch_idx}_#{timestamp}.txt")
      FileUtils.mkdir_p(raw_path.dirname)
      File.write(raw_path, "PROMPT:\n#{prompt}\n\n" + "="*80 + "\n\nRESPONSE:\n#{response}")

      # Clean response (remove any markdown formatting)
      cleaned = response.strip
      cleaned = cleaned.gsub(/^```[a-z]*\s*/i, "")
      cleaned = cleaned.gsub(/```\s*$/, "")
      cleaned = cleaned.strip

      puts "      [DEBUG] Response length: #{response.length}, Cleaned length: #{cleaned.length}"

      # Split by comma to get translations
      translations = cleaned.split(",")

      # Verify we got the expected number of translations
      if translations.length != texts.length
        puts "      ⚠️  Warning: Expected #{texts.length} translations, got #{translations.length}"
        # Pad with empty strings if needed
        while translations.length < texts.length
          translations << ""
        end
        # Truncate if too many
        translations = translations.take(texts.length)
      end

      # Check for empty translations
      empty_count = translations.count { |t| t.nil? || t.strip.empty? }
      if empty_count > 0
        puts "      ⚠️  Warning: #{empty_count}/#{translations.length} translations are empty"
      end

      puts "      [DEBUG] ✓ Parsed #{translations.length} translations"

      translations

    rescue => e
      if retries < max_retries
        retries += 1
        puts "      ⚠️  Translation failed, retry #{retries}/#{max_retries}..."
        puts "      Error: #{e.message}"
        puts "      Response preview: #{response[0..200]}..." if response
        sleep(1)
        retry
      else
        puts "      ⚠️  Translation batch failed after #{max_retries} retries"
        puts "      Error: #{e.message}"
        puts "      Check raw response file for details"
        texts.map { "" }  # Return empty translations on failure
      end
    end
  end

  def build_checkpoint_extraction_prompt(subcriterion_id, text)
    # Keep prompt minimal - system prompt is in Modelfile
    <<~PROMPT
      Extract checkpoints for ASSESSMENT subcriterion: #{subcriterion_id}

      IMPORTANT:
      - Look for "In practice, we find..." sections
      - Extract bullet points (–, •) that are assessment criteria
      - SKIP document sections like "Guiding Principles", "Use Cases", "Case Studies"
      - SKIP explanatory text about EFQM/the model itself

      TEXT:
      #{text}

      Return JSON with "checkpoints" array. Each checkpoint must have: id, parent_id, raw_text.
      Use sequential IDs: #{subcriterion_id}-1, #{subcriterion_id}-2, etc.
      Return empty array if no assessment checkpoints found (only document sections).
    PROMPT
  end

  def find_relevant_pages_for_subcriterion(sub_id, sub_text, page_texts)
    # Find pages with ASSESSMENT content for this subcriterion
    # Need to avoid document sections like "1.1 Guiding Principles" and table of contents
    relevant_pages = []

    # Keywords for both EFQM and KAQA
    efqm_keywords = [ "In practice", "demonstrates sustainable performance", "outstanding organisation" ]
    kaqa_keywords = [ "يتضمن هذا المعيار", "ويمكن أن يشمل ذلك ما يلي" ]
    assessment_keywords = efqm_keywords + kaqa_keywords

    # Table of contents indicators to skip
    toc_indicators = [ "فهرس المعايير", "إجمالي درجة", "Table of Contents", "Contents" ]

    # For RTL reversal: also search for reversed ID (e.g., "4-2" → "2-4")
    reversed_id = nil
    if sub_id.include?("-")
      parts = sub_id.split("-")
      if parts.length == 2 && parts.all? { |p| p.match?(/^\d+$/) }
        reversed_id = "#{parts[1]}-#{parts[0]}"
      end
    end

    page_texts.each_with_index do |page, idx|
      # Skip table of contents pages
      is_toc = toc_indicators.any? { |indicator| page.include?(indicator) }
      next if is_toc

      # Check if page has the subcriterion ID (or reversed ID for KAQA RTL)
      has_id = page.include?(sub_id) || (reversed_id && page.include?(reversed_id))
      has_assessment_language = assessment_keywords.any? { |keyword| page.include?(keyword) }
      has_sub_text = sub_text && page.include?(sub_text[0..50])

      # Only include if it's assessment content (has both ID and assessment language)
      # OR has the subcriterion title text
      if (has_id && has_assessment_language) || has_sub_text
        relevant_pages << page

        # Include next page too (checkpoints might spill over)
        if idx + 1 < page_texts.length
          relevant_pages << page_texts[idx + 1]
        end

        break if relevant_pages.length >= 4
      end
    end

    # If nothing found with strict criteria, fall back to broader search
    # But still skip TOC pages
    if relevant_pages.empty?
      page_texts.each_with_index do |page, idx|
        is_toc = toc_indicators.any? { |indicator| page.include?(indicator) }
        next if is_toc

        has_id = page.include?(sub_id) || (reversed_id && page.include?(reversed_id))
        has_text = sub_text && page.include?(sub_text[0..50])

        if has_id || has_text
          relevant_pages << page
          if idx + 1 < page_texts.length
            relevant_pages << page_texts[idx + 1]
          end
          break if relevant_pages.length >= 3
        end
      end
    end

    relevant_pages.empty? ? page_texts.join("\n\n") : relevant_pages.join("\n\n")
  end

  def find_deepest_subcriteria(all_blocks)
    # Only deepest level subcriteria have checkpoints
    all_blocks.select do |block|
      level = block["level"]
      id = block["id"]

      # Check if any other block has this as parent
      has_children = all_blocks.any? { |b| b["parent_id"] == id }

      # If no children and is subcriterion/nested → can have checkpoints
      !has_children && (level == "subcriterion" || level == "nested_subcriterion")
    end
  end

  def assemble_model(all_blocks, all_checkpoints, standard_type)
    criteria_blocks = all_blocks.select { |b| b["level"] == "criterion" }.sort_by { |b| b["id"].to_i }

    criteria = criteria_blocks.map do |criterion|
      criterion_id = criterion["id"]

      # Find direct children (subcriteria)
      child_subcriteria = all_blocks.select { |b| b["parent_id"] == criterion_id }

      subcriteria = child_subcriteria.map do |sub|
        assemble_subcriterion(sub, all_blocks, all_checkpoints)
      end

      {
        "id" => criterion_id.to_i,
        "name_en" => extract_title(criterion["raw_text"]),
        "name_ar" => "",
        "points" => 0,
        "subcriteria" => subcriteria
      }
    end

    {
      "model" => {
        "name_en" => detect_model_name(standard_type),
        "name_ar" => "",
        "award" => "",
        "total_points" => 1000,
        "principles" => [],
        "criteria" => criteria
      }
    }
  end

  def assemble_subcriterion(subcriterion, all_blocks, all_checkpoints)
    sub_id = subcriterion["id"]

    # Check if it has nested subcriteria
    nested = all_blocks.select { |b| b["parent_id"] == sub_id }

    if nested.any?
      # Has children - assemble them recursively
      {
        "id" => sub_id,
        "name_en" => extract_title(subcriterion["raw_text"]),
        "name_ar" => "",
        "points" => 0,
        "subcriteria" => nested.map { |n| assemble_subcriterion(n, all_blocks, all_checkpoints) }
      }
    else
      # Leaf node - add checkpoints
      checkpoints = all_checkpoints
        .select { |cp| cp["parent_id"] == sub_id }
        .map do |cp|
          {
            "id" => cp["id"],
            "text_en" => cp["raw_text"],
            "text_ar" => ""
          }
        end

      {
        "id" => sub_id,
        "name_en" => extract_title(subcriterion["raw_text"]),
        "name_ar" => "",
        "points" => 0,
        "checkpoints" => checkpoints
      }
    end
  end

  def extract_title(raw_text)
    return "" unless raw_text

    lines = raw_text.split("\n").map(&:strip).reject(&:empty?)
    return "" if lines.empty?

    # First line is usually the title
    title = lines.first

    # Clean up common patterns
    title = title.gsub(/^\d+[\.\-]\s*/, "")
    title = title.gsub(/^(Criterion|Clause)\s*\d+[\.\:]?\s*/i, "")

    title[0..200]
  end

  def detect_model_name(standard_type)
    case standard_type.upcase
    when "EFQM"
      "EFQM Excellence Model 2025"
    when "ISO9001", "ISO 9001"
      "ISO 9001:2015"
    when "ISO27001", "ISO 27001"
      "ISO 27001:2013"
    when "KAQA"
      "King Abdulaziz Quality Award"
    else
      standard_type
    end
  end

  def deduplicate_blocks(blocks)
    # Enhanced deduplication to handle RTL number reversals (e.g., "3-2" vs "2-3")
    seen_ids = Set.new
    seen_reversed_ids = Set.new
    seen_normalized = {}  # normalized_key => block

    deduplicated = []

    blocks.each do |block|
      id = block["id"]
      parent_id = block["parent_id"]
      raw_text = block["raw_text"]

      # Skip if we've seen this exact ID
      next if seen_ids.include?(id)

      # Check for reversed ID (only for hyphenated IDs like "3-2" or "2-3")
      if id.include?("-")
        parts = id.split("-")
        if parts.length == 2 && parts.all? { |p| p.match?(/^\d+$/) }
          reversed_id = "#{parts[1]}-#{parts[0]}"

          # If we've seen the reversed version, check which one is correct
          if seen_ids.include?(reversed_id)
            # The correct ID should have parent_id matching the first part
            expected_parent = parts[0]

            # Find the existing block with reversed ID
            existing = deduplicated.find { |b| b["id"] == reversed_id }

            if existing && existing["parent_id"] != expected_parent && parent_id == expected_parent
              # Current block has correct parent_id, replace the existing one
              deduplicated.delete(existing)
              seen_ids.delete(reversed_id)
              puts "    [DEDUP] Replacing #{reversed_id} with #{id} (correct parent_id: #{parent_id})"
            else
              # Skip current block - existing one is correct
              puts "    [DEDUP] Skipping #{id} - duplicate of #{reversed_id}"
              next
            end
          end
        end
      end

      # Check for duplicate text content (same subcriterion extracted multiple times)
      if raw_text && !raw_text.empty?
        # Normalize text for comparison (remove extra whitespace, lowercase)
        normalized_text = raw_text.strip.gsub(/\s+/, " ").downcase[0..100]
        text_key = "#{parent_id}:#{normalized_text}"

        if seen_normalized[text_key]
          existing = seen_normalized[text_key]
          puts "    [DEDUP] Skipping #{id} - duplicate text of #{existing["id"]} (#{raw_text[0..50]}...)"
          next
        end

        seen_normalized[text_key] = block
      end

      # Add to deduplicated list
      seen_ids.add(id)
      deduplicated << block
    end

    puts "  [DEDUP] Input: #{blocks.length} blocks, Output: #{deduplicated.length} blocks (removed #{blocks.length - deduplicated.length} duplicates)"
    deduplicated
  end

  def clean_json_response(response)
    $stderr.puts "      [CLEAN] Function called"
    $stderr.flush
    return "" unless response

    text = response.strip
    $stderr.puts "      [CLEAN] After strip: #{text.length} bytes"
    $stderr.flush

    # DEBUG: Log initial state
    initial_len = text.length
    $stderr.puts "      [CLEAN DEBUG] Input length: #{initial_len}"
    $stderr.puts "      [CLEAN DEBUG] Last char: #{text[-1].inspect} (byte #{text[-1].ord})"

    # Remove markdown code blocks
    text = text.gsub(/```json\s*/i, "")
    text = text.gsub(/```\s*$/, "")
    text = text.gsub(/^```\s*/, "")

    # Replace smart quotes and special chars
    text = text.gsub(/[\u2018\u2019]/, "'")
    text = text.gsub(/[\u201C\u201D]/, '"')
    text = text.gsub(/[\u2013\u2014]/, "-")
    text = text.gsub(/\u2026/, "...")

    # Remove trailing commas before closing brackets (common LLM mistake)
    before_trailing = text.length
    text = text.gsub(/,(\s*[\]}])/, '\1')
    if text.length != before_trailing
      puts "      [CLEAN DEBUG] Trailing comma removal: #{before_trailing} -> #{text.length} bytes"
    end

    # Fix missing commas between array/object elements (basic cases)
    text = text.gsub(/"\s*\n\s*"/, '",\n"')
    text = text.gsub(/}\s*\n\s*{/, "},\n{")
    text = text.gsub(/]\s*\n\s*\[/, "],\n[")

    # DEBUG: Log before bracket matching
    before_bracket = text.length
    # puts "      [CLEAN DEBUG] Before bracket matching: #{before_bracket}"

    # Find JSON object or array
    json_start = [ text.index("{"), text.index("[") ].compact.min
    if json_start
      text = text[json_start..-1]

      # Find matching closing bracket
      if text.start_with?("{")
        depth = 0
        cut_at = nil
        text.each_char.with_index do |char, idx|
          depth += 1 if char == "{"
          depth -= 1 if char == "}"
          if depth == 0
            cut_at = idx
            text = text[0..idx]
            break
          end
        end
        # puts "      [CLEAN DEBUG] Cut at position #{cut_at}, depth=0"
      elsif text.start_with?("[")
        depth = 0
        text.each_char.with_index do |char, idx|
          depth += 1 if char == "["
          depth -= 1 if char == "]"
          if depth == 0
            text = text[0..idx]
            break
          end
        end
      end
    end

    result = text.strip

    # DEBUG: Log final state
    $stderr.puts "      [CLEAN] Before return: #{result.length} bytes"
    $stderr.puts "      [CLEAN] Last char: #{result[-1].inspect}"
    $stderr.flush
    if result.length != initial_len
      $stderr.puts "      [CLEAN] LENGTH CHANGED: #{initial_len} -> #{result.length}"
      $stderr.flush
    end

    result
  end

  def load_stage_progress(stage_name)
    # Find the most recent progress file for this stage
    pattern = Rails.root.join("tmp", "ollama_responses", "t4_optimized", "progress_#{stage_name}_*.json")
    files = Dir.glob(pattern).sort

    return nil if files.empty?

    latest_file = files.last
    JSON.parse(File.read(latest_file))
  rescue => e
    puts "    Warning: Could not load progress file: #{e.message}"
    nil
  end

  def save_stage_progress(stage_name, data)
    timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
    filepath = Rails.root.join(
      "tmp", "ollama_responses", "t4_optimized",
      "progress_#{stage_name}_#{timestamp}.json"
    )
    FileUtils.mkdir_p(filepath.dirname)
    File.write(filepath, JSON.pretty_generate(data))
    puts "  ✓ Progress saved: #{filepath.basename}"
  end

  def save_raw_response(stage_name, identifier, response, prompt)
    timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
    filename = "raw_#{stage_name}_#{identifier}_#{timestamp}.txt"
    filepath = Rails.root.join("tmp", "ollama_responses", "t4_optimized", "raw", filename)

    FileUtils.mkdir_p(filepath.dirname)

    content = <<~CONTENT
      ============================================
      RAW RESPONSE - #{stage_name.upcase}
      ============================================
      Timestamp: #{Time.current.iso8601}
      Identifier: #{identifier}
      ============================================

      PROMPT:
      #{prompt}

      ============================================

      RAW RESPONSE:
      #{response}

      ============================================
    CONTENT

    File.write(filepath, content)
  rescue => e
    puts "      Warning: Could not save raw response: #{e.message}"
  end

  def save_cleaned_response(stage_name, identifier, json_string)
    timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
    filename = "parsed_#{stage_name}_#{identifier}_#{timestamp}.json"
    filepath = Rails.root.join("tmp", "ollama_responses", "t4_optimized", "parsed", filename)

    FileUtils.mkdir_p(filepath.dirname)
    File.write(filepath, json_string, encoding: "UTF-8")
  rescue => e
    puts "      Warning: Could not save parsed response: #{e.message}"
  end

  def save_failed_response(stage_name, identifier, response, cleaned, error_message)
    timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
    filename = "FAILED_#{stage_name}_#{identifier}_#{timestamp}.txt"
    filepath = Rails.root.join("tmp", "ollama_responses", "t4_optimized", "failed", filename)

    FileUtils.mkdir_p(filepath.dirname)

    content = <<~CONTENT
      ============================================
      FAILED - #{stage_name.upcase}
      ============================================
      Timestamp: #{Time.current.iso8601}
      Identifier: #{identifier}
      Error: #{error_message}
      ============================================

      RAW RESPONSE:
      #{response}

      ============================================

      CLEANED RESPONSE:
      #{cleaned || "(cleaning failed)"}

      ============================================
    CONTENT

    File.write(filepath, content)
    puts "      ✓ Failed response saved: #{filepath}"
  rescue => e
    puts "      Warning: Could not save failed response: #{e.message}"
  end
end
