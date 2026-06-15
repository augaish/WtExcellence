# frozen_string_literal: true

class MultiStagePdfPipeline
  attr_reader :file, :standard_type, :ollama_url, :options

  def initialize(file, standard_type: "EFQM", ollama_url: nil, standard_name: nil, **options)
    @file = file
    @standard_type = standard_type
    @ollama_url = ollama_url || ENV.fetch("OLLAMA_URL", "http://localhost:11434")
    @standard_name = standard_name
    @options = options
    @strategy = PdfPipeline::StandardStrategy.for(standard_type, standard_name: standard_name)
  end

  def process
    log_header

    if debug_save_to_disk?
      @pipeline_run_id = Time.current.strftime("%Y%m%d_%H%M%S")
      Rails.logger.info "Debug: saving LLM input chunks (structure + checkpoint) to tmp/pipeline_chunks/#{@pipeline_run_id}/"
    end

    # Qiyas XLSX: parse directly, then translate
    if @strategy.parse_direct?(file)
      return process_qiyas_xlsx
    end

    process_pdf_pipeline
  end

  private

  def log_header
    Rails.logger.info "=" * 70
    Rails.logger.info "MULTI-STAGE PDF PIPELINE"
    Rails.logger.info "=" * 70
    Rails.logger.info "Standard: #{standard_type}"
    Rails.logger.info "Ollama URL: #{ollama_url}"
    Rails.logger.info "=" * 70
  end

  def process_qiyas_xlsx
    Rails.logger.info "Qiyas XLSX detected: parsing structure directly (no structure/checkpoint extraction)"
    final_model = @strategy.parse_direct(
      file,
      model_display_name: @strategy.model_display_name,
      pipeline_run_id: @pipeline_run_id,
      debug_save: debug_save_to_disk?
    )
    if options[:skip_translation] != true
      Rails.logger.info "\nStage 4: Translating..."
      final_model = run_translation(final_model)
      Rails.logger.info "Translation complete"
    end
    Rails.logger.info "\n" + "=" * 70
    Rails.logger.info "PIPELINE COMPLETE (Qiyas XLSX)"
    Rails.logger.info "=" * 70
    final_model
  end

  def process_pdf_pipeline
    extractor = PdfPipeline::TextExtractor.new(file)
    full_text = extractor.extract_full_text
    cleaned_text = extractor.clean(full_text)
    cleaned_text = @strategy.normalize_text(cleaned_text, **options)
    page_texts = extractor.split_into_pages(cleaned_text)

    Rails.logger.info "Extracted #{page_texts.length} pages"

    Rails.logger.info "\nStage 1: Extracting structure..."
    all_blocks = run_stage1_structure_extraction(page_texts)
    Rails.logger.info "Extracted #{all_blocks.length} structural blocks"

    Rails.logger.info "\nStage 2: Extracting checkpoints..."
    target_subcriteria = find_deepest_subcriteria(all_blocks)
    all_checkpoints = run_stage2_checkpoint_extraction(target_subcriteria, page_texts)
    Rails.logger.info "Extracted #{all_checkpoints.length} checkpoints"

    Rails.logger.info "\nStage 3: Assembling model..."
    combined_blocks = all_blocks.dup
    all_checkpoints.each { |cp| combined_blocks << cp }
    assembler = PdfPipeline::ModelAssembler.new(@strategy.model_display_name)
    final_model = assembler.assemble(combined_blocks)

    if options[:skip_translation] != true
      Rails.logger.info "\nStage 4: Translating..."
      final_model = run_translation(final_model)
      Rails.logger.info "Translation complete"
    end

    Rails.logger.info "\n" + "=" * 70
    Rails.logger.info "PIPELINE COMPLETE"
    Rails.logger.info "=" * 70
    final_model
  end

  STRUCTURE_CHUNK_OVERLAP = 750

  def run_stage1_structure_extraction(page_texts)
    # 1. Build and save ALL structure chunks to disk before any LLM call (for testing/replay)
    # One page per chunk, with overlap from the next page so boundaries aren't lost.
    structure_chunks = []
    page_texts.each_with_index do |page, idx|
      chunk_text = page.dup
      if idx + 1 < page_texts.length
        chunk_text += "\n\n" + page_texts[idx + 1][0..(STRUCTURE_CHUNK_OVERLAP - 1)]
      end
      chunk_num = idx + 1
      prompt = @strategy.structure_prompt(chunk_text)
      structure_chunks << { chunk_text: chunk_text, prompt: prompt, label: "chunk_#{chunk_num.to_s.rjust(3, '0')}" }
    end

    if debug_save_to_disk?
      Rails.logger.info "  Saving #{structure_chunks.size} structure chunks to disk..."
      structure_chunks.each { |c| save_pipeline_chunk("stage1_structure", c[:label], c[:chunk_text], c[:prompt]) }
    end

    # 2. Now call LLM for each chunk
    client = OllamaClient.new(model: @strategy.structure_extraction_model, base_url: ollama_url)
    system_prompt = nil
    all_blocks = []
    structure_chunks.each_with_index do |c, idx|
      total = structure_chunks.size
      Rails.logger.info "  Processing chunk #{idx + 1}/#{total}..."
      all_blocks.concat(call_ollama_blocks(client, c[:prompt], "blocks", system_prompt: system_prompt) { |blocks| Rails.logger.info "    Found #{blocks.length} blocks" })
      sleep(0.2)
    end

    all_blocks = PdfPipeline::BlockDeduplicator.deduplicate(all_blocks)
    ensure_missing_parent_blocks(all_blocks)
  end

  # If any block has parent_id P and no block has id P, add a synthetic block for P (e.g. id "1", raw_text "Clause 1").
  # Repeats until no referenced parent is missing (handles nested gaps e.g. 4.4 and 4).
  def ensure_missing_parent_blocks(blocks)
    loop do
      existing_ids = blocks.map { |b| b["id"].to_s }.compact.to_set
      referenced = blocks.flat_map { |b| [b["parent_id"].to_s].compact }.reject(&:empty?).to_set
      missing = referenced - existing_ids
      break if missing.empty?

      # Add missing parents in order (top-level first, then 4.4 before 4.4.1)
      missing_sorted = missing.sort_by { |id| [id.count("."), id] }
      missing_sorted.each do |pid|
        parent_id = pid.include?(".") ? pid.split(".").tap(&:pop).join(".") : nil
        parent_id = nil if parent_id.to_s.empty?
        blocks << { "id" => pid, "parent_id" => parent_id, "raw_text" => "Clause #{pid}" }
        Rails.logger.info "    Added missing parent block: id \"#{pid}\", raw_text \"Clause #{pid}\""
      end
    end
    blocks
  end

  def run_stage2_checkpoint_extraction(target_subcriteria, page_texts)
    pages_finder = PdfPipeline::RelevantPagesFinder.new(@strategy)

    # 1. Build and save ALL checkpoint chunks to disk before any LLM call (for testing/replay)
    checkpoint_chunks = []
    target_subcriteria.each_with_index do |subcriterion, idx|
      sub_id = subcriterion["id"]
      relevant_text = pages_finder.find(sub_id, subcriterion["raw_text"], page_texts)
      prompt = @strategy.checkpoint_prompt(sub_id, relevant_text)
      checkpoint_chunks << { sub_id: sub_id, relevant_text: relevant_text, prompt: prompt, label: "sub_#{sanitize_chunk_label(sub_id)}" }
    end

    if debug_save_to_disk?
      Rails.logger.info "  Saving #{checkpoint_chunks.size} checkpoint chunks to disk..."
      checkpoint_chunks.each { |c| save_pipeline_chunk("stage2_checkpoints", c[:label], c[:relevant_text], c[:prompt]) }
    end

    # 2. Now call LLM for each chunk
    client = OllamaClient.new(model: @strategy.checkpoint_extraction_model, base_url: ollama_url)
    system_prompt = @strategy.respond_to?(:checkpoint_system_prompt) ? @strategy.checkpoint_system_prompt : nil
    all_checkpoints = []
    checkpoint_chunks.each_with_index do |c, idx|
      Rails.logger.info "    Processing #{c[:sub_id]} (#{idx + 1}/#{checkpoint_chunks.length})..."
      all_checkpoints.concat(call_ollama_blocks(client, c[:prompt], "checkpoints", system_prompt: system_prompt) { |cps| Rails.logger.info "      Found #{cps.length} checkpoints" })
      sleep(0.2)
    end

    PdfPipeline::BlockDeduplicator.deduplicate(all_checkpoints)
  end

  def call_ollama_blocks(client, prompt, key, system_prompt: nil, max_retries: 2)
    retries = 0
    begin
      response = client.generate(prompt, system: system_prompt)
      cleaned = response.strip
        .gsub(/^```json\s*/i, "")
        .gsub(/^```\s*/, "")
        .gsub(/```\s*$/, "")
        .strip
      parsed = JSON.parse(cleaned)
      blocks = parsed[key] || []
      yield blocks if block_given?
      blocks
    rescue JSON::ParserError => e
      if retries < max_retries
        retries += 1
        Rails.logger.warn "    JSON parse failed, retry #{retries}/#{max_retries}..."
        sleep(1)
        retry
      else
        Rails.logger.error "    JSON parse error after #{max_retries} retries: #{e.message}"
        []
      end
    rescue => e
      Rails.logger.error "    Error: #{e.message}"
      []
    end
  end

  def find_deepest_subcriteria(all_blocks)
    all_blocks.select do |block|
      id = block["id"]
      next false if block["parent_id"].blank? # top-level criteria
      # Leaf = no other block (except checkpoints) has this block as parent
      has_non_checkpoint_children = all_blocks.any? { |b| b["parent_id"] == id && !checkpoint_block?(b) }
      !has_non_checkpoint_children
    end
  end

  # Checkpoint = requirement under a subcriterion (e.g. "4.1-1", "1-1-1"). Not "1-1" with parent "1" (N-M subcriterion).
  def checkpoint_block?(block)
    pid = block["parent_id"].to_s
    return false if pid.empty?
    id = block["id"].to_s
    return false unless id.start_with?("#{pid}-") && id[pid.length + 1..].match?(/^\d+$/)
    pid.include?(".") || pid.include?("-")
  end

  def run_translation(model)
    source_lang_hint = @strategy.respond_to?(:document_source_language) ? @strategy.document_source_language : nil
    PdfPipeline::TranslationRunner.new(
      ollama_url: ollama_url,
      debug_save: debug_save_to_disk?,
      source_lang_hint: source_lang_hint
    ).run(model)
  end

  def debug_save_to_disk?
    Rails.env.development? || options[:save_chunks_for_testing] == true
  end

  # Saves only the chunk text (and prompt) sent to the LLM. Does not save raw pages or full text.
  def save_pipeline_chunk(stage, label, input_text, prompt)
    return unless debug_save_to_disk? && @pipeline_run_id
    base = Rails.root.join("tmp", "pipeline_chunks", @pipeline_run_id, stage)
    FileUtils.mkdir_p(base)
    File.write(base.join("#{label}_input.txt"), input_text.to_s)
    File.write(base.join("#{label}_prompt.txt"), prompt.to_s)
    Rails.logger.info "    Debug: saved chunk #{label}"
  rescue => e
    Rails.logger.warn "    Could not save pipeline chunk: #{e.message}"
  end

  def sanitize_chunk_label(id)
    id.to_s.gsub(/[^\w\-.]/, "_").gsub(".", "_")
  end
end
