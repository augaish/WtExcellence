
require "base64"
require "tempfile"
require "fileutils"
require "shellwords"

class StandardIngestionService
  # Optimized chunk size for detailed extraction
  # 35K chars = ~8,750 tokens per chunk (leaves room for comprehensive outputs)
  # Larger chunks = fewer API calls + better context for complete Criterion extraction
  MAX_CHUNK_SIZE = 35_000

  # on_progress: optional callback invoked with a stage key ("extracting_text",
  # "ai_analysis") as the pipeline advances, so callers (the ingestion job) can
  # surface live progress to the UI.
  def initialize(pdf_file, on_progress: nil)
    @pdf_file = pdf_file
    @on_progress = on_progress

    # Configure OpenRouter
    OpenRouter.configure do |config|
      config.access_token = ENV.fetch("OPENROUTER_API_KEY")
      config.site_name = "Way to Excellence"
      config.site_url = ENV.fetch("APP_URL", "http://localhost:3000")
    end

    @client = OpenRouter::Client.new

    @model = ENV.fetch("OPENROUTER_MODEL", "anthropic/claude-sonnet-4.5")

    Rails.logger.info "Using OpenRouter with model: #{@model}"
  end

  def extract_chunks(pdf_file)
    # Prefer the embedded text layer (instant) and only fall back to slow OCR
    # for scanned/image PDFs — see extract_text_smart.
    text = extract_text_smart(pdf_file)

    # Return as a single chunk (no chunking - process entire document at once)
    [ text ]
  end

  # Digital PDFs already carry a selectable text layer that PDF::Reader can pull
  # out in milliseconds; only scanned/image PDFs actually need OCR. OCR
  # (rasterize every page at high DPI + run Tesseract) is the slow path, so we
  # use it ONLY when the text layer is missing or unusable. Set
  # INGESTION_FORCE_OCR=1 to always OCR (e.g. for a scan with a garbage layer).
  def extract_text_smart(pdf_file)
    if ENV["INGESTION_FORCE_OCR"] == "1"
      Rails.logger.info "INGESTION_FORCE_OCR=1 — skipping text-layer check, running OCR"
      return extract_text_from_pdf_images(pdf_file)
    end

    layer = begin
      extract_text_from_pdf_reader(pdf_file)
    rescue => e
      Rails.logger.warn "Text-layer extraction failed: #{e.message}"
      ""
    end

    pages = pdf_page_count(pdf_file)
    if usable_text_layer?(layer, pages)
      Rails.logger.info "Using embedded PDF text layer (#{layer.gsub(/\s/, '').length} chars over ~#{pages} pages) — skipping OCR"
      return layer
    end

    Rails.logger.info "Text layer sparse/unusable — falling back to OCR"
    extract_text_from_pdf_images(pdf_file)
  end

  # True when the text layer has enough real letters to trust as a digital PDF
  # (avoids trusting a near-empty or garbage layer, which would feed the LLM junk).
  def usable_text_layer?(text, pages)
    return false if text.blank? || pages.to_i <= 0
    dense = text.gsub(/\s/, "")
    return false if dense.length < 200
    return false if dense.length < 40 * pages
    letters = dense.scan(/[A-Za-z؀-ۿ]/).length
    (letters.to_f / dense.length) >= 0.5
  end

  def pdf_page_count(pdf_file)
    PDF::Reader.new(StringIO.new(pdf_file.blob.download)).page_count
  rescue => e
    Rails.logger.warn "Could not count PDF pages: #{e.message}"
    0
  end

  def extract_text_from_pdf_images(pdf_file)
    # Check if pdftoppm is available
    unless system("which pdftoppm > /dev/null 2>&1")
      Rails.logger.warn "pdftoppm not found. Install poppler-utils: brew install poppler (macOS) or apt-get install poppler-utils (Linux)"
      Rails.logger.warn "Falling back to PDF::Reader method"
      return extract_text_from_pdf_reader(pdf_file)
    end

    # Check if tesseract is available
    unless system("which tesseract > /dev/null 2>&1")
      Rails.logger.warn "tesseract not found. Install tesseract: brew install tesseract tesseract-lang (macOS) or apt-get install tesseract-ocr tesseract-ocr-ara (Linux)"
      Rails.logger.warn "Falling back to PDF::Reader method"
      return extract_text_from_pdf_reader(pdf_file)
    end

    # Download PDF to temp file
    pdf_data = pdf_file.blob.download
    temp_pdf = Tempfile.new([ "pdf", ".pdf" ], encoding: "ASCII-8BIT")
    temp_pdf.write(pdf_data)
    temp_pdf.rewind
    temp_pdf.close

    # Convert PDF pages to images using pdftoppm (from poppler-utils)
    images_dir = Dir.mktmpdir
    begin
      # Convert PDF to PNG images (one per page). DPI drives both OCR speed and
      # memory: 300 DPI produces ~8.7MP images per A4 page (slow, RAM-heavy on a
      # small box). 200 is a good speed/accuracy balance for printed standards;
      # drop to 150 via INGESTION_OCR_DPI if uploads still crawl.
      dpi = ENV.fetch("INGESTION_OCR_DPI", "200").to_i
      dpi = 200 unless dpi.positive?
      pdf_path = Shellwords.escape(temp_pdf.path)
      output_prefix = Shellwords.escape(File.join(images_dir, "page"))
      success = system("pdftoppm -png -r #{dpi} #{pdf_path} #{output_prefix}")

      unless success
        Rails.logger.error "Failed to convert PDF to images"
        return extract_text_from_pdf_reader(pdf_file)
      end

      # Get all page images
      page_images = Dir.glob(File.join(images_dir, "page-*.png")).sort

      if page_images.empty?
        Rails.logger.error "No images generated from PDF"
        return extract_text_from_pdf_reader(pdf_file)
      end

      Rails.logger.info "Converted PDF to #{page_images.length} page images"

      # Detect available OCR languages ONCE (not once per page — that spawned a
      # `tesseract --list-langs` subprocess for every page).
      lang_string = tesseract_lang_string

      # Extract text from each page image using Tesseract OCR
      all_text = ""
      page_images.each_with_index do |image_path, index|
        Rails.logger.info "Extracting text from page #{index + 1}/#{page_images.length} using Tesseract (#{lang_string})..."
        page_text = extract_text_from_image_with_tesseract(image_path, lang_string)
        all_text += page_text + "\n"
      end

      # Log a sample of the extracted text
      sample_text = all_text[0..500]
      arabic_chars = sample_text.scan(/[\u0600-\u06FF]/).length
      Rails.logger.info "Extracted text from #{page_images.length} pages (#{all_text.length} chars, #{arabic_chars} Arabic characters in first 500 chars)"

      # Save extracted text to file for debugging
      save_extracted_text(all_text, page_images.length)

      all_text
    ensure
      # Cleanup
      FileUtils.rm_rf(images_dir)
      temp_pdf.unlink
    end
  rescue => e
    Rails.logger.error "Error extracting text from PDF images: #{e.message}"
    Rails.logger.error "Backtrace: #{e.backtrace.first(5).join("\n")}"
    Rails.logger.error "Falling back to PDF::Reader method"
    # Fallback to original method
    extract_text_from_pdf_reader(pdf_file)
  end

  def extract_text_from_pdf_reader(pdf_file)
    file_io = StringIO.new(pdf_file.blob.download)
    reader = PDF::Reader.new(file_io)

    text = ""
    reader.pages.each do |page|
      page_text = page.text
      page_text = page_text.force_encoding("UTF-8") unless page_text.valid_encoding?
      page_text = clean_pdf_text(page_text)
      text += page_text + "\n"
    end

    text
  end

  # Detect the Tesseract language string once. Honors INGESTION_OCR_LANGS
  # (e.g. "ara" for an Arabic-only doc — single language is ~2x faster than
  # "eng+ara"); otherwise auto-detects installed languages.
  def tesseract_lang_string
    return @tesseract_lang_string if defined?(@tesseract_lang_string)

    override = ENV["INGESTION_OCR_LANGS"].to_s.strip
    if override.present?
      return @tesseract_lang_string = override
    end

    available_langs = `tesseract --list-langs 2>&1`.scan(/^([a-z_]+)$/).flatten
    languages = []
    languages << "eng" if available_langs.include?("eng")
    languages << "ara" if available_langs.include?("ara") || available_langs.include?("ara_script")
    languages = [ "eng" ] if languages.empty?

    @tesseract_lang_string = languages.join("+")
  end

  def extract_text_from_image_with_tesseract(image_path, lang_string = nil)
    lang_string ||= tesseract_lang_string

    # Run Tesseract OCR
    # -l: specify languages
    # --psm 6: Assume a single uniform block of text
    # --oem 3: Use LSTM OCR Engine
    escaped_image_path = Shellwords.escape(image_path)
    output_file = File.join(File.dirname(image_path), "ocr_output_#{File.basename(image_path, '.png')}")
    escaped_output = Shellwords.escape(output_file)

    # Tesseract command: tesseract input.png output -l eng+ara --psm 6
    cmd = "tesseract #{escaped_image_path} #{escaped_output} -l #{lang_string} --psm 6 --oem 3 2>&1"

    Rails.logger.debug "Running Tesseract command: #{cmd}"
    result = `#{cmd}`
    exit_code = $?.exitstatus

    if exit_code != 0
      Rails.logger.error "Tesseract OCR failed with exit code #{exit_code}: #{result}"
      return ""
    end

    # Read the output text file (Tesseract creates .txt file)
    text_file = "#{output_file}.txt"
    if File.exist?(text_file)
      text = File.read(text_file, encoding: "UTF-8")
      # Clean up the temporary text file
      File.delete(text_file) rescue nil

      # Clean the extracted text
      cleaned = clean_pdf_text(text)
      Rails.logger.info "Extracted #{cleaned.length} chars from image using Tesseract"
      cleaned
    else
      Rails.logger.error "Tesseract output file not found: #{text_file}"
      ""
    end
  rescue => e
    Rails.logger.error "Error extracting text with Tesseract: #{e.message}"
    Rails.logger.error "Backtrace: #{e.backtrace.first(5).join("\n")}"
    ""
  end

  def clean_pdf_text(text)
    # Ensure UTF-8 encoding to preserve Arabic characters
    cleaned = text.dup.force_encoding("UTF-8")

    # Remove invalid UTF-8 characters that might corrupt Arabic text
    unless cleaned.valid_encoding?
      cleaned = cleaned.encode("UTF-8", "UTF-8", invalid: :replace, undef: :replace)
    end

    # 1. Fix words run together with no space before capital letters (English only)
    # "sustainableValue" -> "sustainable Value"
    # Only apply to ASCII characters to avoid corrupting Arabic
    cleaned = cleaned.gsub(/([a-z])([A-Z])/, '\1 \2')

    # 2. Fix words run together: "forits" -> "for its", "isvital" -> "is vital"
    # Common patterns: isX, forX, ofX, atX, toX
    # Only apply to ASCII words to avoid corrupting Arabic
    cleaned = cleaned.gsub(/\b(is|for|of|at|to|in)([a-z]{2,})\b/i) do |match|
      word1 = $1
      word2 = $2
      # Check if word2 is likely a real word (heuristic: has vowels)
      if word2.match?(/[aeiou]/i)
        "#{word1} #{word2}"
      else
        match # Keep original if doesn't look like a word
      end
    end

    # 3. Normalize excessive whitespace but preserve paragraph breaks
    cleaned = cleaned.gsub(/[ \t]+/, " ")  # Multiple spaces/tabs to single space
    cleaned = cleaned.gsub(/\n\s+\n/, "\n\n")  # Preserve paragraph breaks

    # 4. Remove trailing/leading spaces on each line
    cleaned = cleaned.lines.map(&:strip).join("\n")

    cleaned
  end

  def process_pdf
    # Extract text from PDF (or test file)
    @on_progress&.call("extracting_text")
    chunks = extract_chunks(@pdf_file)
    @on_progress&.call("ai_analysis")

    # For testing: Process as single prompt (no chunking)
    if chunks.length == 1
      Rails.logger.info "Processing entire document in single prompt (#{chunks[0].length} chars)"
      text = chunks[0]

      # Build single prompt with all text
      prompt = build_single_prompt(text)

      # Single API call
      response = call_openrouter_api(prompt, use_system_prompt: true)

      # Save LLM response to file for debugging
      save_llm_response(response)

      # Parse response
      begin
        cleaned = clean_response_text(response)
        parsed = JSON.parse(cleaned)

        if parsed["model"] && parsed["model"]["criteria"] && parsed["model"]["criteria"].is_a?(Array)
          criteria_count = parsed["model"]["criteria"].length
          subcriteria_count = parsed["model"]["criteria"].sum { |c| c["subcriteria"]&.length || 0 }
          checkpoint_count = parsed["model"]["criteria"].sum do |c|
            c["subcriteria"]&.sum { |sc| sc["checkpoints"]&.length || 0 } || 0
          end

          Rails.logger.info "✅ Successfully extracted: #{criteria_count} criteria, #{subcriteria_count} subcriteria, #{checkpoint_count} checkpoints"

          # Return in the new format
          parsed
        else
          raise "No model.criteria array in response"
        end
      rescue => e
        Rails.logger.error "Failed to parse response: #{e.class} - #{e.message}"
        {
          "model" => {
            "name_ar" => "",
            "name_en" => "",
            "award" => "",
            "total_points" => 0,
            "principles" => [],
            "criteria" => []
          },
          "error" => e.message,
          "processing_method" => "single_prompt_failed"
        }
      end
    else
      # Fallback to chunked processing if multiple chunks (shouldn't happen in test mode)
      Rails.logger.warn "Multiple chunks detected, falling back to chunked processing"
      raw_responses = process_chunks(chunks)

      if raw_responses.any?
        Rails.logger.info "Combining #{raw_responses.length} chunk responses..."
        combine_raw_responses(raw_responses)
      else
        Rails.logger.warn "No responses to combine"
        {
          "clauses" => [],
          "metadata" => {
            "provider" => "openrouter",
            "model" => @model,
            "processing_method" => "no_responses",
            "error" => "No chunks were processed"
          }
        }
      end
    end
  end

  def process_chunks(chunks)
    raw_responses = []
    previous_clauses_summary = []

    chunks.each_with_index do |chunk_text, index|
      # Build prompt with context from previous chunks
      prompt = build_chunk_prompt(chunk_text, index, chunks.length, previous_clauses_summary)

      response = call_openrouter_api(prompt, use_system_prompt: true)

      raw_responses << {
        chunk_index: index + 1,
        raw_text: response,
        chunk_length: chunk_text.length
      }

      # Extract clauses from this response to build context for next chunk
      begin
        cleaned = clean_response_text(response)
        parsed = JSON.parse(cleaned)
        if parsed["clauses"] && parsed["clauses"].is_a?(Array)
          # Add new clauses to the summary (accumulate, don't replace)
          new_clauses = build_clauses_summary(parsed["clauses"])
          previous_clauses_summary.concat(new_clauses)
          Rails.logger.info "Extracted #{parsed['clauses'].length} clauses from chunk #{index + 1}, total clauses so far: #{previous_clauses_summary.length}"
        end
      rescue => e
        Rails.logger.warn "Could not parse chunk #{index + 1} response for context: #{e.message}"
        # Continue without updating context
      end

      wait_time = 10
      Rails.logger.info "Waiting #{wait_time} seconds before next chunk..."
      sleep(wait_time)
    end

    # Return raw responses for combination
    raw_responses
  end



  def call_openrouter_api(prompt, use_system_prompt: true)
    begin
      Rails.logger.info "Calling OpenRouter API with model: #{@model}"
      Rails.logger.info "Prompt length: #{prompt.length} chars"

      messages = []

      # Add system prompt for extraction tasks
      if use_system_prompt
        messages << {
          role: "system",
          content: build_system_prompt
        }
      end

      # Add user prompt
      messages << {
        role: "user",
        content: prompt
      }

      # Use the open_router gem's complete method
      response = @client.complete(
        messages,
        model: @model
      )

      if response.nil?
        Rails.logger.error "OpenRouter API returned nil response"
        Rails.logger.error "Model: #{@model}, Prompt length: #{prompt.length} chars"
        raise "API returned nil response"
      end

      content = response.dig("choices", 0, "message", "content")

      if content.nil?
        Rails.logger.error "Failed to extract content from response"
        Rails.logger.error "Response structure: #{response.keys.inspect}" if response.is_a?(Hash)
        Rails.logger.error "Full response: #{response.inspect}"
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

  private

  def build_system_prompt
    <<~SYSTEM
      You are an expert in analyzing quality management standards such as EFQM (English), ISO 9001 (English), ISO 14001 (English), ISO 27001 (English), and KAQA (Arabic).

      You will receive text that may be in English, Arabic, or mixed (both languages).

      CRITICAL: The text may contain garbled or corrupted characters due to PDF extraction issues. You MUST still extract clauses even if text is corrupted.

      MANDATORY REQUIREMENTS:
      - You MUST output valid JSON with clauses, even if the text is corrupted
      - Extract what you CAN understand from the text - do not refuse to extract
      - SKIP TABLE OF CONTENTS: Quality standard documents have a table of contents/introduction section listing all clauses. DO NOT extract clauses from this table. Skip it and start extracting from the actual content sections.
      - IDENTIFY TABLE OF CONTENTS: Look for patterns like "Table of Contents", "Contents", "Introduction", or sections that just list clause numbers/titles without detailed content. Skip these sections.
      - EXTRACT FROM ACTUAL CONTENT: Only extract clauses from sections that contain actual detailed content, requirements, descriptions, or checkpoints - not from summary tables or TOC.
      - EXTRACT CRITERIA IN ORDER: Start from criterion 1, then subcriterion 1-1, 1-2, then criterion 2, 2-1, 2-2, etc. Extract ALL criteria and subcriteria sequentially from the actual content (after skipping TOC).
      - LANGUAGE HANDLING:
        * If the source text is in ARABIC, extract Arabic text directly into "name_ar", "text_ar" fields and translate to English for "name_en", "text_en" fields
        * If the source text is in ENGLISH, extract English text into "name_en", "text_en" fields and TRANSLATE to Arabic for "name_ar", "text_ar" fields
        * If the source text is MIXED (both languages), extract each language into its respective fields
        * CRITICAL: For ALL English-only documents (EFQM, ISO 9001, ISO 14001, ISO 27001, or any other English standard), you MUST translate all English content to Arabic. Do not leave Arabic fields empty or use "[Translation needed]" for English-only documents.
        * MANDATORY: Every English document must have complete Arabic translations - this applies to ISO standards, EFQM, and any other English quality management standard.
        * Only use "[Translation needed]" when text is CORRUPTED/UNREADABLE, not when you can translate it
        * Always provide bilingual content: both English and Arabic fields should be populated
      - NUMBERING FORMAT:
        * KAQA (Arabic): Uses DASHES for subcriteria IDs - "1-1", "1-2", "1-3", "2-1", etc. (NOT dots!)
        * Checkpoint IDs use DASHES - "1-1-1", "1-1-2", "1-2-1", etc. (NOT dots!)
        * If you see "1-2" or "2-3" in Arabic text, that's a subcriterion ID, not "1.2" or "2.3"
        * Preserve the original numbering format from the source document
      - ARABIC TEXT DIRECTION:
        * Arabic text is read RIGHT-TO-LEFT (RTL)
        * Extract Arabic text as it appears in the source, maintaining RTL order
        * Arabic words like "ادارة", "مراجعة", "الجودة" should be extracted in their original RTL order
      - If you see criterion codes (like "1", "1-1", "1-2", "2-1", etc.), extract them with whatever readable content you can find
      - NEVER refuse to extract - always output JSON with at least the structure you can identify
      - Focus on extracting criterion IDs, subcriterion IDs, checkpoint IDs, names, and text
      - EXTRACT FROM THE BEGINNING: Don't skip to criterion 5 or later - start from criterion 1 and extract sequentially
      - Include model metadata (name_ar, name_en, award, total_points) if available in the document
      - Include principles if they are listed in the document

      Your goal is to extract the hierarchical structure of criteria, subcriteria, and checkpoints, and generate bilingual content (English and Arabic). The output must strictly follow the provided JSON schema with model, principles, criteria, subcriteria, and checkpoints.

      ### Core Rules

      1. SKIP TABLE OF CONTENTS: Do NOT extract criteria from table of contents, introduction tables, or summary sections that just list criterion numbers. Skip these and start from the actual content sections.
      2. EXTRACT IN ORDER: Start from criterion 1 in the actual content (after TOC), then extract sequentially: 1, 1-1, 1-2, 2, 2-1, etc. Extract ALL criteria and subcriteria from the content sections.
      3. NUMBERING FORMAT:
         - KAQA (Arabic): Uses DASHES for subcriteria IDs - "1-1", "1-2", "1-3", "2-1" (NOT dots!)
         - Checkpoint IDs use DASHES - "1-1-1", "1-1-2", "1-2-1" (NOT dots!)
         - Preserve the original format from the source document
      4. Structure:#{' '}
         - Criteria contain subcriteria
         - Subcriteria can contain nested subcriteria (for ISO 9001: "1.1" contains "1.1.1", "1.1.2", etc.)
         - Only the deepest level subcriteria contain checkpoints
         - For ISO 9001: "1" → "1.1" → "1.1.1" → checkpoints (if any)
         - For KAQA/EFQM: "1" → "1-1" or "1.1" → checkpoints
      5. ISO 9001 HIERARCHY: ISO 9001 has 3+ levels. "1.1.1" is a SUBCRITERION (child of "1.1"), NOT a checkpoint. Only the deepest level (e.g., "1.1.1.1" or items under "1.1.1") should be checkpoints.
      6. Maintain factual meaning from the source text; do not invent new requirements.
      7. LANGUAGE EXTRACTION AND TRANSLATION RULES:
         - If source text is ARABIC: Extract Arabic text into "name_ar", "text_ar" fields and TRANSLATE to English for "name_en", "text_en" fields
         - If source text is ENGLISH: Extract English text into "name_en", "text_en" fields and TRANSLATE to Arabic for "name_ar", "text_ar" fields
         - If source text is MIXED: Extract each language into its respective fields and translate missing languages
         - CRITICAL: For ALL English-only documents (EFQM, ISO 9001, ISO 14001, ISO 27001, or any other English standard), you MUST translate all English content to Arabic. Never leave Arabic fields empty for English documents.
         - MANDATORY: Every English document must have complete Arabic translations - this applies to ISO standards, EFQM, and any other English quality management standard.
         - Only use "[Translation needed]" when text is CORRUPTED/UNREADABLE, not when you can translate it
         - Always provide bilingual content: both English and Arabic fields must be populated
         - Arabic text is RTL - extract/translate it maintaining proper RTL order
      11. You MUST output valid JSON even if text is corrupted - extract what you can and use placeholders for corrupted parts.
      12. NEVER refuse to extract or say the text is too corrupted - always produce JSON output.
      13. Output must be valid JSON only — do not include any explanations, commentary, or Markdown formatting.

      ### Output Schema
      {
        "model": {
          "name_ar": "string",
          "name_en": "string",
          "award": "string",
          "total_points": number,
          "principles": [
            {
              "id": number,
              "name_ar": "string",
              "name_en": "string"
            }
          ],
          "criteria": [
            {
              "id": number,
              "name_ar": "string",
              "name_en": "string",
              "points": number,
              "subcriteria": [
                {
                  "id": "string (e.g., 1-1, 1-2, 2-1, 1.1, 4.1)",
                  "name_ar": "string",
                  "name_en": "string",
                  "points": number,
                  "subcriteria": [
                    {
                      "id": "string (e.g., 1.1.1, 4.1.1) - NESTED subcriterion for ISO 9001",
                      "name_ar": "string",
                      "name_en": "string",
                      "points": number,
                      "checkpoints": [
                        {
                          "id": "string (e.g., 1-1-1, 1-1-2, 2-1-1, 1.1.1.1)",
                          "text_ar": "string",
                          "text_en": "string"
                        }
                      ]
                    }
                  ],
                  "checkpoints": [
                    {
                      "id": "string (e.g., 1-1-1, 1-1-2, 2-1-1) - only if no nested subcriteria",
                      "text_ar": "string",
                      "text_en": "string"
                    }
                  ]
                }
              ]
            }
          ]
        }
      }

      ### Examples:

      Example 1 - KAQA (Arabic) with DASHES:
      If you see Arabic text like "1-2 ادارة الجودة" (note the DASH, not dot!), extract:
      {
        "model": {
          "name_ar": "النموذج الوطني للتميز المؤسسي 2022",
          "name_en": "National Excellence Model 2022",
          "award": "King Abdulaziz Quality Award",
          "total_points": 1000,
          "principles": [
            {
              "id": 1,
              "name_ar": "القيادة بالإلهام والقدوة الحسنة",
              "name_en": "Leadership by Inspiration and Good Example"
            }
          ],
          "criteria": [
            {
              "id": 1,
              "name_ar": "القيادة الإدارية",
              "name_en": "Leadership",
              "points": 120,
              "subcriteria": [
                {
                  "id": "1-2",
                  "name_ar": "ادارة الجودة",
                  "name_en": "Quality Management",
                  "points": 20,
                  "checkpoints": [
                    {
                      "id": "1-2-1",
                      "text_ar": "Extracted Arabic text here",
                      "text_en": "Translated English text here"
                    }
                  ]
                }
              ]
            }
          ]
        }
      }
      NOTE: KAQA uses DASHES for subcriteria IDs (1-2, 1-3) and checkpoint IDs (1-2-1, 1-2-2) NOT dots!

      Example 1b - EFQM (English) with DOTS - MUST TRANSLATE TO ARABIC:
      If you see English text like "1.1 Quality Management", extract and TRANSLATE:
      {
        "model": {
          "name_ar": "نموذج التميز الأوروبي",
          "name_en": "EFQM Excellence Model",
          "award": "EFQM Excellence Award",
          "total_points": 1000,
          "principles": [],
          "criteria": [
            {
              "id": 1,
              "name_ar": "القيادة",
              "name_en": "Leadership",
              "points": 100,
              "subcriteria": [
                {
                  "id": "1.1",
                  "name_ar": "إدارة الجودة",
                  "name_en": "Quality Management",
                  "points": 50,
                  "checkpoints": [
                    {
                      "id": "1.1.1",
                      "text_ar": "النص العربي المترجم هنا",
                      "text_en": "Extracted English text here"
                    }
                  ]
                }
              ]
            }
          ]
        }
      }
      NOTE: EFQM uses DOTS (1.1, 1.2) NOT dashes. CRITICAL: Translate ALL English content to Arabic!

      Example 1c - ISO 9001 (English) with NESTED SUBCRITERIA - MUST TRANSLATE TO ARABIC:
      ISO 9001 has 3+ levels: "1" → "1.1" → "1.1.1" → checkpoints. "1.1.1" is a SUBCRITERION, NOT a checkpoint!
      If you see English text like "4.1 Understanding the organization and its context" with "4.1.1" as a sub-item, extract:
      {
        "model": {
          "name_ar": "ISO 9001:2015",
          "name_en": "ISO 9001:2015",
          "award": "",
          "total_points": 0,
          "principles": [],
          "criteria": [
            {
              "id": 4,
              "name_ar": "السياق التنظيمي",
              "name_en": "Context of the organization",
              "points": 0,
              "subcriteria": [
                {
                  "id": "4.1",
                  "name_ar": "فهم المنظمة وسياقها",
                  "name_en": "Understanding the organization and its context",
                  "points": 0,
                  "subcriteria": [
                    {
                      "id": "4.1.1",
                      "name_ar": "فهم المنظمة وسياقها - التفاصيل",
                      "name_en": "Understanding the organization and its context - Details",
                      "points": 0,
                      "checkpoints": [
                        {
                          "id": "4.1.1.1",
                          "text_ar": "النص العربي المترجم هنا",
                          "text_en": "Extracted English text here"
                        }
                      ]
                    }
                  ]
                }
              ]
            }
          ]
        }
      }
      CRITICAL FOR ISO 9001:
      - "1.1.1" is a SUBCRITERION (child of "1.1"), NOT a checkpoint
      - Subcriteria can be nested: "1" → "1.1" → "1.1.1" → "1.1.1.1" (checkpoint)
      - Only the deepest level contains checkpoints
      - Translate ALL English content to Arabic

      Example 2 - Corrupted Text:
      If you see corrupted text like "1-2 ادارة [corrupted chars]", extract what you can:
      {
        "model": {
          "name_ar": "Extracted from document",
          "name_en": "Extracted from document",
          "award": "Extracted from document",
          "total_points": 1000,
          "principles": [],
          "criteria": [
            {
              "id": 1,
              "name_ar": "Extracted from corrupted text",
              "name_en": "[Translation needed]",
              "points": 0,
              "subcriteria": [
                {
                  "id": "1-2",
                  "name_ar": "ادارة [corrupted]",
                  "name_en": "[Translation needed]",
                  "points": 0,
                  "checkpoints": []
                }
              ]
            }
          ]
        }
      }

      NEVER output explanations - ALWAYS output JSON, even if minimal.
    SYSTEM
  end


  # PHASE 2: Combine raw responses into valid JSON
  def combine_raw_responses(raw_responses)
    if raw_responses.empty?
      return {
        "clauses" => [],
        "metadata" => {
          "provider" => "openrouter",
          "model" => @model,
          "processing_method" => "combination_failed",
          "error" => "No raw responses to combine"
        }
      }
    end

    Rails.logger.info "Phase 2: Combining #{raw_responses.length} raw responses..."

    # Build the prompt with all raw responses
    combination_prompt = build_combination_prompt(raw_responses)

    begin
      # Single LLM call to combine, fix, and deduplicate everything
      raw_combined = call_openrouter_api(combination_prompt, use_system_prompt: false)
      cleaned_combined = clean_response_text(raw_combined)

      # Parse final JSON
      combined_data = JSON.parse(cleaned_combined)

      if combined_data["clauses"] && combined_data["clauses"].is_a?(Array)
        clause_count = combined_data["clauses"].length
        checkpoint_count = combined_data["clauses"].sum { |c| c["checkpoints"]&.length || 0 }

        Rails.logger.info "✅ Successfully combined: #{clause_count} clauses, #{checkpoint_count} checkpoints"

        {
          "clauses" => combined_data["clauses"],
          "metadata" => {
            "provider" => "openrouter",
            "model" => @model,
            "chunks_processed" => raw_responses.length,
            "total_clauses" => clause_count,
            "total_checkpoints" => checkpoint_count,
            "processing_method" => "single_pass_combination"
          }
        }
      else
        raise "No clauses array in combined response"
      end

    rescue => e
      Rails.logger.error "Combination failed: #{e.class} - #{e.message}"
      Rails.logger.error "Attempting local parsing fallback..."

      # Fallback: Parse each response locally
      fallback_parse_raw_responses(raw_responses)
    end
  end

  # Fallback: Retry combination with explicit JSON fixing instructions
  def fallback_parse_raw_responses(raw_responses)
    Rails.logger.info "Fallback: Retrying combination with stricter JSON instructions..."

    # Build a simpler prompt focused on JSON fixing
    fallback_prompt = build_fallback_combination_prompt(raw_responses)

    begin
      # Retry with explicit JSON repair instructions
      Rails.logger.info "Attempting combination retry with JSON repair focus..."
      raw_combined = call_openrouter_api(fallback_prompt, use_system_prompt: false)
      cleaned_combined = clean_response_text(raw_combined)

      combined_data = JSON.parse(cleaned_combined)

      if combined_data["clauses"] && combined_data["clauses"].is_a?(Array)
        clause_count = combined_data["clauses"].length
        checkpoint_count = combined_data["clauses"].sum { |c| c["checkpoints"]&.length || 0 }

        Rails.logger.info "✅ Retry successful: #{clause_count} clauses, #{checkpoint_count} checkpoints"

        return {
          "clauses" => combined_data["clauses"],
          "metadata" => {
            "provider" => "openrouter",
            "model" => @model,
            "chunks_processed" => raw_responses.length,
            "total_clauses" => clause_count,
            "total_checkpoints" => checkpoint_count,
            "processing_method" => "fallback_combination_retry"
          }
        }
      end
    rescue => e
      Rails.logger.error "Fallback retry also failed: #{e.class} - #{e.message}"
    end

    # Last resort: try local parsing (may lose data)
    local_parse_fallback(raw_responses)
  end

  # Last resort: Parse locally (may lose malformed chunks)
  def local_parse_fallback(raw_responses)
    Rails.logger.warn "Final fallback: Local parsing (may lose malformed data)..."

    all_clauses = []

    raw_responses.each do |response|
      begin
        cleaned = clean_response_text(response[:raw_text])
        data = JSON.parse(cleaned)

        if data["clauses"] && data["clauses"].is_a?(Array)
          all_clauses.concat(data["clauses"])
          Rails.logger.info "✅ Parsed chunk #{response[:chunk_index]}: #{data['clauses'].length} clauses"
        end
      rescue => e
        Rails.logger.error "⚠️  Could not parse chunk #{response[:chunk_index]}: #{e.message}"
        Rails.logger.error "⚠️  This chunk's data is LOST"
      end
    end

    clause_count = all_clauses.length
    checkpoint_count = all_clauses.sum { |c| c["checkpoints"]&.length || 0 }

    Rails.logger.warn "⚠️  Local parsing complete: #{clause_count} clauses, #{checkpoint_count} checkpoints"
    Rails.logger.warn "⚠️  Some data may have been lost due to malformed JSON"

    {
      "clauses" => all_clauses,
      "metadata" => {
        "provider" => "openrouter",
        "model" => @model,
        "chunks_processed" => raw_responses.length,
        "total_clauses" => clause_count,
        "total_checkpoints" => checkpoint_count,
        "processing_method" => "local_parsing_fallback_with_data_loss"
      }
    }
  end

  def split_text_into_chunks(text)
    # Try to split at Criterion boundaries for EFQM documents
    # This ensures each chunk contains relevant Criterion content

    # First, try to detect Criterion sections
    criterion_positions = []
    text.scan(/\n\s*(Criterion\s+\d+|Direction|Execution|Results)/i) do |match|
      criterion_positions << { position: Regexp.last_match.begin(0), text: match[0] }
    end

    if criterion_positions.length >= 2
      Rails.logger.info "Detected #{criterion_positions.length} Criterion/section markers, using smart chunking"
      return split_by_criterion_boundaries(text, criterion_positions)
    end

    # Fallback: Split by paragraphs (for ISO or other documents)
    Rails.logger.info "No Criterion markers detected, using paragraph-based chunking"
    split_by_paragraphs(text)
  end

  def split_by_criterion_boundaries(text, criterion_positions)
    chunks = []
    current_chunk_start = 0

    criterion_positions.each_with_index do |marker, index|
      next if index == 0 # Skip first marker, include it in first chunk

      # Check if we should start a new chunk here
      chunk_length = marker[:position] - current_chunk_start

      if chunk_length >= MAX_CHUNK_SIZE
        # Create chunk from start to this marker
        chunks << text[current_chunk_start...marker[:position]].strip
        current_chunk_start = marker[:position]
        Rails.logger.info "Created chunk at '#{marker[:text]}' boundary (#{chunk_length} chars)"
      end
    end

    # Add the last chunk
    if current_chunk_start < text.length
      chunks << text[current_chunk_start..-1].strip
    end

    # If we got very few chunks, fall back to paragraph splitting
    if chunks.length < 2 && text.length > MAX_CHUNK_SIZE
      Rails.logger.info "Smart chunking produced too few chunks, falling back to paragraph splitting"
      return split_by_paragraphs(text)
    end

    chunks
  end

  def split_by_paragraphs(text)
    # Split by paragraphs to avoid breaking sentences
    paragraphs = text.split(/\n\n+/)

    chunks = []
    current_chunk = ""

    paragraphs.each do |paragraph|
      # If adding this paragraph would exceed chunk size, start a new chunk
      if current_chunk.length >= MAX_CHUNK_SIZE && current_chunk.length > 0
        chunks << current_chunk.strip
        current_chunk = paragraph
      else
        current_chunk += "\n\n" + paragraph
      end
    end

    # Add the last chunk
    chunks << current_chunk.strip if current_chunk.length > 0

    chunks
  end

  def build_chunk_prompt(chunk_text, chunk_index, total_chunks, previous_clauses_summary = [])
    context_section = if previous_clauses_summary.any?
      <<~PREVIOUS
        IMPORTANT CONTEXT FROM PREVIOUS CHUNKS:
        The following clauses have already been extracted from previous chunks in this document:
        #{previous_clauses_summary.map { |c| "- Code: #{c[:code]}, Title: #{c[:title_en]}, Stable Key: #{c[:stable_key]}" }.join("\n")}

        RULES FOR THIS CHUNK:
        1. Do NOT duplicate clauses that already exist above.
        2. If you find a clause with a code that already exists, skip it (it was already extracted).
        3. Maintain consistency with existing stable_key patterns.
        4. Ensure parent_code relationships are correct if referencing previously extracted clauses.
        5. Only extract NEW clauses that haven't been seen in previous chunks.

      PREVIOUS
    else
      <<~FIRST
        This is the FIRST chunk of the document. Extract all clauses you find.

      FIRST
    end

    <<~CONTEXT
      You are analyzing a portion of a quality management standard. Extract the hierarchical clauses and subclauses from the text below, and generate bilingual (English and Arabic) audit checkpoints strictly according to the JSON schema provided in the system prompt.

      Chunk #{chunk_index + 1} of #{total_chunks}.

      #{context_section}
      Rules to follow:
      1. SKIP TABLE OF CONTENTS: Do NOT extract clauses from table of contents or introduction sections. Skip sections that just list clause numbers/titles without detailed content. Start extracting from actual content sections.
      2. EXTRACT IN ORDER: Start from clause 1 in the actual content (after TOC) and extract sequentially. Don't skip to later clauses - extract from the beginning of content.
      3. NUMBERING FORMAT:
         - EFQM (English): Uses dots - "1", "1.1", "1.2", "2", "2.1"
         - KAQA (Arabic): Uses DASHES - "1", "1-2", "1-3", "2", "2-1" (NOT "1.2" or "2.1"!)
         - Preserve the original format from the source
      4. Only final-level (leaf) clauses should contain checkpoints.
      5. Parent clauses with subclauses should contain metadata and summaries only.
      6. Preserve hierarchy using `parent_code`.
      7. Each clause and checkpoint must have a unique `stable_key`.
      8. Do not invent new requirements; keep factual meaning.
      9. MANDATORY: You MUST extract clauses even if text is corrupted. Do not refuse to extract.
      10. LANGUAGE EXTRACTION:
         - If source text is ARABIC: Extract Arabic text into "title_ar", "text_ar", "guidance_ar" fields
         - If source text is ENGLISH: Extract English text into "title_en", "text_en", "guidance_en" fields
         - If source text is MIXED: Extract each language into its respective fields
         - Only use "[Translation needed]" when text is CORRUPTED/UNREADABLE
         - If you see readable Arabic text, extract it directly into Arabic fields - don't mark as needing translation
         - Arabic is RTL - extract text as it appears
      11. Focus on extracting clause codes (numbers like "1", "1.1", "1-2", "2.3", "2-1"), titles (even if partial), and structure from ACTUAL CONTENT sections.
      12. If you see any readable words (English or Arabic), extract them into the appropriate language fields.
      13. NEVER output explanations about text being corrupted - always output valid JSON with extracted clauses.
      14. Output must be valid JSON only, no explanations or formatting.

      Here is the text chunk:
      #{chunk_text}
    CONTEXT
  end


  def build_combination_prompt(raw_responses)
    # Format all raw responses
    formatted_responses = raw_responses.map do |response|
      "===== CHUNK #{response[:chunk_index]} (#{response[:chunk_length]} chars) =====\n#{response[:raw_text]}\n"
    end.join("\n\n")

    <<~PROMPT
      You are combining multiple LLM responses from a chunked PDF document.
      Each response may contain JSON with clauses (possibly malformed or incomplete).

      YOUR TASK:
      1. Extract ALL content from ALL chunks (even if JSON is malformed)
      2. Fix any JSON syntax errors:
         - Fix incomplete field names (e.g., "_ar" → "guidance_ar")
         - Fix incomplete stable_keys (e.g., "_1_3" → "chk_1_3" or "clause_1_3")
         - Fix missing quotes, commas, brackets
         - Remove trailing commas before ] or }
         - Complete any truncated strings
      3. Combine all clauses into one array
      4. Deduplicate clauses with same code (keep most complete version)
      5. Sort hierarchically: "1", "1.1", "1.2", "2", "2.1", etc.
      6. Verify parent_code relationships
      7. Merge checkpoints from duplicates

      CRITICAL - MUST RETURN VALID JSON:
      - Return ONLY parseable JSON (no markdown, no explanations)
      - Start with { and end with }
      - Format: { "clauses": [ ... ] }
      - ALL field names complete and quoted
      - ALL strings with matching quotes
      - NO trailing commas
      - Include ALL clauses from ALL chunks (don't lose data!)

      RAW RESPONSES (may contain syntax errors - fix them!):

      #{formatted_responses}

      Return ONLY valid JSON starting with { and ending with }:
    PROMPT
  end

  def build_fallback_combination_prompt(raw_responses)
    # Simpler, more focused prompt for retry
    formatted_responses = raw_responses.map do |response|
      "===== CHUNK #{response[:chunk_index]} =====\n#{response[:raw_text]}\n"
    end.join("\n\n")

    <<~PROMPT
      EMERGENCY JSON REPAIR TASK

      The responses below contain JSON syntax errors. Your job is to:
      1. Read ALL the content (even malformed parts)
      2. Extract every clause you can find
      3. Return 100% VALID, PARSEABLE JSON

      Common errors to fix:
      - Missing quotes: "field_name": value → "field_name": "value"
      - Incomplete fields: "_ar" → "guidance_ar"
      - Trailing commas: [...,] → [...]
      - Unclosed strings: "text → "text"
      - Missing brackets: { "x": → { "x": "" }

      CRITICAL: Your output MUST be valid JSON that can be parsed.
      Format: { "clauses": [ ... ] }
      No markdown, no code blocks, no explanations.
      Start with { and end with }.

      MALFORMED RESPONSES TO FIX:

      #{formatted_responses}

      Return ONLY valid JSON:
    PROMPT
  end

  def clean_response_text(raw_text)
    cleaned_text = raw_text.strip
    if cleaned_text.start_with?("```json")
      cleaned_text = cleaned_text.gsub(/^```json\s*/, "").gsub(/\s*```$/, "")
    elsif cleaned_text.start_with?("```")
      cleaned_text = cleaned_text.gsub(/^```\s*/, "").gsub(/\s*```$/, "")
    end
    cleaned_text
  end

  def build_clauses_summary(clauses)
    # Build a lightweight summary of extracted clauses for context
    clauses.map do |clause|
      {
        code: clause["code"],
        title_en: clause["title_en"] || clause["title"] || "",
        stable_key: clause["stable_key"] || "",
        parent_code: clause["parent_code"]
      }
    end
  end

  def build_single_prompt(text)
    <<~PROMPT
      You are analyzing a quality management standard document. Extract the hierarchical clauses and subclauses from the text below, and generate bilingual (English and Arabic) audit checkpoints strictly according to the JSON schema provided in the system prompt.

      This is the ENTIRE document - extract ALL clauses from it.

      Rules to follow:
      1. SKIP TABLE OF CONTENTS: Do NOT extract criteria from table of contents or introduction sections. Skip sections that just list criterion numbers/titles without detailed content. Start extracting from actual content sections.
      2. EXTRACT IN ORDER: Start from criterion 1 in the actual content (after TOC) and extract sequentially. Don't skip to later criteria - extract from the beginning of content.
      3. NUMBERING FORMAT:
         - KAQA (Arabic): Uses DASHES for subcriteria IDs - "1-1", "1-2", "1-3", "2-1" (NOT "1.1" or "2.1"!)
         - Checkpoint IDs use DASHES - "1-1-1", "1-1-2", "1-2-1" (NOT "1.1.1" or "1.2.1"!)
         - Preserve the original format from the source
      4. Structure:#{' '}
         - Criteria contain subcriteria
         - Subcriteria can contain nested subcriteria (for ISO 9001: "1.1" contains "1.1.1", "1.1.2", etc.)
         - Only the deepest level subcriteria contain checkpoints
         - For ISO 9001: "1" → "1.1" → "1.1.1" → checkpoints (if any)
         - For KAQA/EFQM: "1" → "1-1" or "1.1" → checkpoints
      5. ISO 9001 HIERARCHY: ISO 9001 has 3+ levels. "1.1.1" is a SUBCRITERION (child of "1.1"), NOT a checkpoint. Only the deepest level (e.g., "1.1.1.1" or items under "1.1.1") should be checkpoints.
      6. Do not invent new requirements; keep factual meaning.
      7. MANDATORY: You MUST extract criteria even if text is corrupted. Do not refuse to extract.
      8. LANGUAGE EXTRACTION AND TRANSLATION:
         - If source text is ARABIC: Extract Arabic text into "name_ar", "text_ar" fields and TRANSLATE to English for "name_en", "text_en" fields
         - If source text is ENGLISH: Extract English text into "name_en", "text_en" fields and TRANSLATE to Arabic for "name_ar", "text_ar" fields
         - If source text is MIXED: Extract each language into its respective fields and translate missing languages
         - CRITICAL: For ALL English-only documents (EFQM, ISO 9001, ISO 14001, ISO 27001, or any other English standard), you MUST translate all English content to Arabic. Never leave Arabic fields empty.
         - MANDATORY: Every English document must have complete Arabic translations - this applies to ISO standards, EFQM, and any other English quality management standard.
         - Only use "[Translation needed]" when text is CORRUPTED/UNREADABLE
         - Always provide bilingual content: both English and Arabic fields must be populated
         - Arabic is RTL - translate maintaining proper RTL order
      9. Focus on extracting criterion IDs (numbers like "1", "2", "3"), subcriterion IDs (like "1-1", "1-2", "2-1"), checkpoint IDs (like "1-1-1", "1-1-2"), names, and text from ACTUAL CONTENT sections.
      10. If you see any readable words (English or Arabic), extract them into the appropriate language fields.
      11. NEVER output explanations about text being corrupted - always output valid JSON with extracted criteria.
      12. Output must be valid JSON only, no explanations or formatting.
      13. Extract ALL criteria from the document - this is the complete text, so extract everything.
      14. Include model metadata (name_ar, name_en, award, total_points) if available in the document.
      15. Include principles array if principles are listed in the document.

      Here is the complete document text:
      #{text}
    PROMPT
  end

  def save_extracted_text(text, page_count)
    timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
    filename = "extracted_text_from_images_#{timestamp}.txt"
    filepath = Rails.root.join("tmp", "chunks", filename)

    FileUtils.mkdir_p(Rails.root.join("tmp", "chunks"))

    metadata = <<~METADATA
      ============================================
      EXTRACTED TEXT FROM PDF IMAGES
      ============================================
      Timestamp: #{Time.current.iso8601}
      Pages processed: #{page_count}
      Total characters: #{text.length}
      Arabic characters: #{text.scan(/[\u0600-\u06FF]/).length}
      Extraction method: Tesseract OCR
      ============================================

    METADATA

    File.write(filepath, metadata + text)

    Rails.logger.info "✅ Extracted text saved to: #{filepath}"
    Rails.logger.info "File size: #{File.size(filepath)} bytes"
  end

  def save_llm_response(response_text)
    timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
    filename = "llm_response_#{timestamp}.txt"
    filepath = Rails.root.join("tmp", "chunks", filename)

    FileUtils.mkdir_p(Rails.root.join("tmp", "chunks"))

    metadata = <<~METADATA
      ============================================
      LLM RESPONSE
      ============================================
      Timestamp: #{Time.current.iso8601}
      Model: #{@model}
      Response length: #{response_text.length} characters
      Processing method: Single prompt (no chunking)
      ============================================

    METADATA

    File.write(filepath, metadata + response_text)

    Rails.logger.info "✅ LLM response saved to: #{filepath}"
    Rails.logger.info "File size: #{File.size(filepath)} bytes"

    # Also try to save as JSON if it's valid JSON
    begin
      cleaned = clean_response_text(response_text)
      parsed = JSON.parse(cleaned)

      json_filename = "llm_response_#{timestamp}.json"
      json_filepath = Rails.root.join("tmp", "chunks", json_filename)
      File.write(json_filepath, JSON.pretty_generate(parsed))

      Rails.logger.info "✅ LLM response (JSON) saved to: #{json_filepath}"
    rescue => e
      Rails.logger.warn "Could not save JSON version: #{e.message}"
    end
  end
end
