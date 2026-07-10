class ProcessIngestionJob
  include Sidekiq::Job

  # Dedicated single-threaded queue (see the "ingestion" capsule in
  # config/initializers/sidekiq.rb) so heavy OCR/LLM work runs one-at-a-time and
  # never thrashes memory alongside other ingestion or light jobs. Fewer retries
  # because each attempt is minutes long — 5 retries of a stuck job storm a small box.
  sidekiq_options queue: :ingestion, retry: 2

  # Custom retry logic for rate limits
  sidekiq_retry_in do |count, exception|
    case exception
    when Faraday::TooManyRequestsError
      # Exponential backoff: 30s, 60s, 120s, 240s, 480s
      30 * (2 ** count)
    else
      # Default retry: 5s, 10s, 20s, 40s, 80s
      5 * (2 ** count)
    end
  end

  def perform(ingestion_job_id)
    ingestion_job = IngestionJob.find(ingestion_job_id)

    Rails.logger.info "Processing ingestion job: #{ingestion_job_id}"


    # Mark the job as processing OUTSIDE any transaction, so the status is
    # committed immediately and visible to the UI and monitoring while the long
    # OCR/LLM work runs. Only the database writes below are wrapped in a
    # transaction — never the external OCR/LLM calls, which could otherwise hold
    # a DB connection open for minutes.
    ingestion_job.start_processing!

    begin
      upload = ingestion_job.input_pdf
      standard = ingestion_job.standard

      Rails.logger.info "Upload ID: #{upload.id}, file attached: #{upload.file.attached?}"

      unless upload.file.attached?
        Rails.logger.error "No file attached to upload #{upload.id}"
        raise "No file attached to upload #{upload.id}"
      end

      Rails.logger.info "Processing PDF file: #{upload.filename} for standard: #{standard.code}"

      # Find existing version with this source PDF
      standard_version = StandardVersion.find_by(source_pdf_id: upload.id)

      unless standard_version
        Rails.logger.error "No standard version found for source_pdf_id: #{upload.id}"
        raise "No standard version found for source PDF"
      end

      Rails.logger.info "Using existing standard version: #{standard_version.id}, label: #{standard_version.version_label}"

      # If this version already has USABLE clauses (e.g. re-run or retry), skip
      # the LLM. A tree whose titles are all empty (saved by a run that fed the
      # LLM unreadable text) is NOT usable — purge it and reprocess, otherwise
      # every retry would instantly "complete" while the tree stays empty.
      if standard_version.clauses.exists?
        if version_has_titled_clauses?(standard_version)
          Rails.logger.info "Version #{standard_version.id} already has titled clauses. Skipping LLM."
          ingestion_job.complete!("Version already had clauses. No processing needed.")
          return
        else
          Rails.logger.warn "Version #{standard_version.id} has clauses but ALL titles are empty — purging and reprocessing."
          ActiveRecord::Base.transaction { standard_version.clauses.where(parent_id: nil).destroy_all }
        end
      end

      # For EFQM/KAQA family (code or name contains "efqm" or "kaqa"): don't process again — copy from any
      # already-processed EFQM/KAQA standard. E.g. superadmin uploads EFQM (we process once), then EFQM2
      # an hour later: we copy EFQM's clause tree to EFQM2 and skip the LLM.
      if efqm_or_kaqa_standard?(standard)
        source_version = find_existing_version_with_clauses(standard, standard_version)
        source_version ||= find_any_efqm_kaqa_version_with_clauses(standard, standard_version)

        if source_version
          Rails.logger.info "EFQM/KAQA cache hit: copying clauses from version #{source_version.id} (#{source_version.version_label}). Skipping LLM."
          ActiveRecord::Base.transaction { copy_clauses_from_version!(source_version, standard_version) }
          ingestion_job.complete!("Clause tree copied from existing version (EFQM/KAQA cache).")
          return
        end

        Rails.logger.info "EFQM/KAQA cache miss: no existing version with clauses (code=#{standard.code}, display_name=#{standard.display_name('en')}). Will run LLM."
      end

      # Choose service based on configuration (LLM runs only when cache was not used)
      # - MultiStagePdfPipeline: Uses Ollama models (qwen-extract-structure, qwen-extract-checkpoints, qwen-translator)
      # - StandardIngestionService: Uses OpenRouter API (OpenAI/Anthropic models)
      service_type = ENV.fetch("INGESTION_SERVICE", "multi_stage") # Options: "multi_stage" or "openrouter"

      if service_type == "multi_stage" && ENV["OLLAMA_URL"].present?
        Rails.logger.info "Using MultiStagePdfPipeline with Ollama (#{ENV['OLLAMA_URL']})"
        pipeline_type = standard.pipeline_type.presence || standard.code
        Rails.logger.info "Pipeline type: #{pipeline_type}"

        service = MultiStagePdfPipeline.new(
          upload.file,
          standard_type: pipeline_type,
          standard_name: standard.display_name("en"),
          ollama_url: ENV["OLLAMA_URL"]
        )
        ingestion_job.set_stage!("ai_analysis")
        parsed_data = service.process

        # Save output to file for debugging/backup
        timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
        output_path = Rails.root.join(
          "tmp", "ollama_responses", "t4_optimized",
          "standard_t4_#{standard.code.downcase}_#{timestamp}.json"
        )
        FileUtils.mkdir_p(output_path.dirname)
        File.write(output_path, JSON.pretty_generate(parsed_data))
        Rails.logger.info "Output saved to: #{output_path}"

        # Convert multi-stage format to database format and save
        ingestion_job.set_stage!("saving_clauses")
        ActiveRecord::Base.transaction { convert_and_save_multi_stage_data(standard_version, parsed_data) }

        Rails.logger.info "Multi-stage pipeline completed and saved to database."
        ingestion_job.complete!("PDF processed successfully using multi-stage pipeline (Ollama). Output: #{output_path.basename}")

      elsif service_type == "openrouter" || ENV["OLLAMA_URL"].blank?
        Rails.logger.info "Using StandardIngestionService with OpenRouter"

        service = StandardIngestionService.new(
          upload.file,
          # stage transitions update the stage; every call refreshes the
          # heartbeat + per-page detail (e.g. "12/80") for the live UI and the
          # stale-job reaper.
          on_progress: lambda { |stage, detail = nil|
            ingestion_job.set_stage!(stage) if ingestion_job.progress_stage != stage.to_s
            ingestion_job.heartbeat!(detail)
          }
        )
        parsed_data = service.process_pdf

        # process_pdf returns the { "model" => { "criteria" => [...] } } schema —
        # the SAME shape as the multi-stage pipeline — so convert it the same way.
        # (The old process_extracted_clauses expected a "clauses" key that no
        # longer exists, which crashed with "undefined method 'length' for nil".)
        # Surface an extraction/parse failure instead of saving an empty tree.
        if parsed_data["error"].present?
          raise "Standard extraction failed: #{parsed_data['error']}"
        end
        unless extraction_has_titles?(parsed_data)
          raise "Detected the document structure but the clause titles came back empty — the source text was likely unreadable (e.g. an Arabic PDF whose text layer is garbled). Re-upload the PDF; set INGESTION_FORCE_OCR=1 if it's a scan."
        end

        ingestion_job.set_stage!("saving_clauses")
        ActiveRecord::Base.transaction { convert_and_save_multi_stage_data(standard_version, parsed_data) }

        Rails.logger.info "OpenRouter service completed and saved to database."
        ingestion_job.complete!("PDF processed successfully using StandardIngestionService (OpenRouter).")

      else
        raise "Unknown INGESTION_SERVICE type: #{service_type}. Use 'multi_stage' or 'openrouter'"
      end

    rescue => e
      Rails.logger.error "Error processing ingestion job #{ingestion_job_id}: #{e.message}"
      Rails.logger.error "Backtrace: #{e.backtrace.first(5)}"

      ingestion_job.fail!("Processing failed: #{e.message}")

      # Re-raise the error to trigger Sidekiq retry mechanism
      raise e
    end
  end

  private

  # Guards against the "empty skeleton" failure: the LLM returned criteria (the
  # numbering structure) but every title is blank, which means the extracted
  # text was empty/garbage. Returns false so the job fails with a clear reason
  # instead of silently saving titleless clauses.
  def extraction_has_titles?(parsed_data)
    criteria = parsed_data.dig("model", "criteria")
    return true unless criteria.is_a?(Array) && criteria.any?

    criteria.any? do |c|
      c["name_en"].to_s.strip.present? || c["name_ar"].to_s.strip.present?
    end
  end

  def efqm_or_kaqa_standard?(standard)
    return true if standard.pipeline_type == "efqm"
    name_for_check = [standard.code, standard.display_name("en")].compact.join(" ").downcase
    name_for_check.include?("efqm") || name_for_check.include?("kaqa")
  end

  def find_existing_version_with_clauses(standard, exclude_version)
    standard.standard_versions
      .where.not(id: exclude_version.id)
      .joins(:clauses)
      .distinct
      .reorder(id: :asc)
      .detect { |v| version_has_titled_clauses?(v) }
  end

  # Only versions whose clauses actually have titles are valid cache sources —
  # never copy a previously-saved empty/garbage skeleton onto a new upload.
  def version_has_titled_clauses?(version)
    ClauseTranslation.joins(:clause)
      .where(clauses: { standard_version_id: version.id })
      .where.not(title: [ nil, "" ])
      .exists?
  end

  # Fallback: another standard in the *same* sub-family (EFQM with EFQM, KAQA with KAQA) that has a version with clauses.
  # EFQM4 copies from EFQM; KAQA copies from KAQA. Never copy across EFQM ↔ KAQA (different languages).
  def find_any_efqm_kaqa_version_with_clauses(standard, exclude_version)
    name_for_check = [standard.code, standard.display_name("en")].compact.join(" ").downcase
    # Decide sub-family from name/code: KAQA (Arabic) vs EFQM (English). Prefer KAQA if both appear.
    match_kaqa = name_for_check.include?("kaqa") || name_for_check.include?("king abdulaziz")
    match_efqm = name_for_check.include?("efqm") && !match_kaqa

    same_family_standard_ids = if match_kaqa
      # KAQA: match code/name containing "kaqa" OR "king abdulaziz" (don't use pipeline_type — it's shared with EFQM)
      ids_by_code = Standard.where("LOWER(code) LIKE ? OR LOWER(code) LIKE ?", "%kaqa%", "%king abdulaziz%").pluck(:id)
      ids_by_name = Standard
        .joins(:standard_translations)
        .where("LOWER(standard_translations.name) LIKE ? OR LOWER(standard_translations.name) LIKE ?", "%kaqa%", "%king abdulaziz%")
        .distinct
        .pluck(:id)
      (ids_by_code + ids_by_name).uniq
    elsif match_efqm
      # EFQM: match code/name containing "efqm" but NOT kaqa/king abdulaziz (so we don't pull in KAQA)
      ids_by_code = Standard.where("LOWER(code) LIKE ?", "%efqm%")
        .where("LOWER(code) NOT LIKE ? AND LOWER(code) NOT LIKE ?", "%kaqa%", "%king abdulaziz%")
        .pluck(:id)
      ids_by_name = Standard
        .joins(:standard_translations)
        .where("LOWER(standard_translations.name) LIKE ?", "%efqm%")
        .where("LOWER(standard_translations.name) NOT LIKE ? AND LOWER(standard_translations.name) NOT LIKE ?", "%kaqa%", "%king abdulaziz%")
        .distinct
        .pluck(:id)
      (ids_by_code + ids_by_name).uniq
    else
      []
    end
    return nil if same_family_standard_ids.blank?

    StandardVersion
      .where(standard_id: same_family_standard_ids)
      .where.not(id: exclude_version.id)
      .joins(:clauses)
      .distinct
      .reorder(id: :asc)
      .detect { |v| version_has_titled_clauses?(v) }
  end

  def copy_clauses_from_version!(source_version, target_version)
    old_to_new_clause = {}
    source_version.clauses.root_clauses.ordered.each do |old_root|
      copy_clause_recursive(old_root, target_version, old_to_new_clause)
    end
  end

  def copy_clause_recursive(old_clause, target_version, old_to_new_clause)
    new_parent = old_clause.parent_id ? old_to_new_clause[old_clause.parent_id] : nil
    new_clause = Clause.create!(
      standard_version: target_version,
      parent: new_parent,
      code: old_clause.code,
      sort_order: old_clause.sort_order,
      stable_key: old_clause.stable_key,
      allocated_points: old_clause.allocated_points,
      base_points: old_clause.base_points
    )
    old_to_new_clause[old_clause.id] = new_clause

    old_clause.clause_translations.each do |ct|
      ClauseTranslation.create!(
        clause: new_clause,
        language_code: ct.language_code,
        title: ct.title,
        summary: ct.summary,
        body: ct.body,
        needs_review: ct.needs_review,
        ai_generated: ct.ai_generated
      )
    end

    old_clause.checklist_items.ordered.each do |old_ci|
      new_ci = ChecklistItem.create!(
        clause: new_clause,
        code: old_ci.code,
        item_type: old_ci.item_type,
        sort_order: old_ci.sort_order,
        stable_key: old_ci.stable_key
      )
      old_ci.checklist_item_translations.each do |cit|
        ChecklistItemTranslation.create!(
          checklist_item: new_ci,
          language_code: cit.language_code,
          text: cit.text,
          guidance: cit.guidance,
          needs_review: cit.needs_review,
          ai_generated: cit.ai_generated
        )
      end
    end

    old_clause.children.ordered.each do |old_child|
      copy_clause_recursive(old_child, target_version, old_to_new_clause)
    end
  end

  # Convert multi-stage pipeline format to database format
  def convert_and_save_multi_stage_data(standard_version, parsed_data)
    clauses_data = []

    criteria = parsed_data.dig("model", "criteria") || []

    criteria.each do |criterion|
      # Add criterion as a clause
      criterion_clause = {
        "code" => criterion["id"].to_s,
        "title_en" => criterion["name_en"],
        "title_ar" => criterion["name_ar"],
        "summary_en" => "",
        "summary_ar" => "",
        "parent_code" => nil,
        "stable_key" => "criterion_#{criterion['id']}",
        "checkpoints" => []
      }
      clauses_data << criterion_clause

      # Process subcriteria recursively
      (criterion["subcriteria"] || []).each do |subcriterion|
        process_subcriterion(clauses_data, subcriterion, criterion["id"].to_s)
      end
    end

    # Save to database using existing method
    process_extracted_clauses(standard_version, clauses_data)
  end

  # Recursively process subcriteria and nested subcriteria
  def process_subcriterion(clauses_data, subcriterion, parent_code)
    sub_clause = {
      "code" => subcriterion["id"].to_s,
      "title_en" => subcriterion["name_en"],
      "title_ar" => subcriterion["name_ar"],
      "summary_en" => "",
      "summary_ar" => "",
      "parent_code" => parent_code,
      "stable_key" => "subcriterion_#{subcriterion['id']}",
      "checkpoints" => []
    }

    # Add checkpoints if present
    if subcriterion["checkpoints"] && subcriterion["checkpoints"].is_a?(Array)
      subcriterion["checkpoints"].each do |checkpoint|
        sub_clause["checkpoints"] << {
          "code" => checkpoint["id"].to_s,
          "text_en" => checkpoint["text_en"],
          "text_ar" => checkpoint["text_ar"],
          "item_type" => "requirement",
          "stable_key" => "checkpoint_#{checkpoint['id']}",
          "guidance_en" => "",
          "guidance_ar" => ""
        }
      end
    end

    clauses_data << sub_clause

    # Process nested subcriteria recursively
    if subcriterion["subcriteria"] && subcriterion["subcriteria"].is_a?(Array)
      subcriterion["subcriteria"].each do |nested|
        process_subcriterion(clauses_data, nested, subcriterion["id"].to_s)
      end
    end
  end

  def process_extracted_clauses(standard_version, clauses_data)
    Rails.logger.info "Processing #{clauses_data.length} clauses"

    # First pass: create all clauses and store them in a hash for parent lookup
    clauses_by_code = {}

    clauses_data.each_with_index do |clause_data, index|
      parent_clause = nil
      if clause_data["parent_code"].present?
        parent_clause = clauses_by_code[clause_data["parent_code"]]
      end

      # Use find_or_create_by to handle duplicate clauses from overlapping chunks
      clause = Clause.find_or_create_by(
        standard_version: standard_version,
        code: clause_data["code"] || "#{index + 1}"
      ) do |c|
        c.parent = parent_clause
        c.sort_order = index
        c.stable_key = clause_data["stable_key"]
      end

      clauses_by_code[clause.code] = clause

      # Create or update English translation
      if clause_data["title_en"].present?
        ClauseTranslation.find_or_create_by(
          clause: clause,
          language_code: "en"
        ) do |ct|
          ct.title = clause_data["title_en"]
          ct.summary = clause_data["summary_en"]
          ct.body = clause_data["summary_en"]
        end
      end

      # Create or update Arabic translation
      if clause_data["title_ar"].present?
        ClauseTranslation.find_or_create_by(
          clause: clause,
          language_code: "ar"
        ) do |ct|
          ct.title = clause_data["title_ar"]
          ct.summary = clause_data["summary_ar"]
          ct.body = clause_data["summary_ar"]
        end
      end

      if clause_data["checkpoints"] && clause_data["checkpoints"].is_a?(Array)
        process_checklist_items(clause, clause_data["checkpoints"])
      end
    end
  end

  def process_checklist_items(clause, checkpoints_data)
    Rails.logger.info "Processing #{checkpoints_data.length} checkpoints for clause #{clause.code}"

    checkpoints_data.each_with_index do |checkpoint_data, index|
      # Use find_or_create_by to handle duplicate checkpoints
      checklist_item = ChecklistItem.find_or_create_by(
        clause: clause,
        code: checkpoint_data["code"]
      ) do |ci|
        ci.item_type = checkpoint_data["item_type"] || "requirement"
        ci.sort_order = index
        ci.stable_key = checkpoint_data["stable_key"]
      end

      # Create or update English translation
      if checkpoint_data["text_en"].present?
        ChecklistItemTranslation.find_or_create_by(
          checklist_item: checklist_item,
          language_code: "en"
        ) do |cit|
          cit.text = checkpoint_data["text_en"]
          cit.guidance = checkpoint_data["guidance_en"]
        end
      end

      # Create or update Arabic translation
      if checkpoint_data["text_ar"].present?
        ChecklistItemTranslation.find_or_create_by(
          checklist_item: checklist_item,
          language_code: "ar"
        ) do |cit|
          cit.text = checkpoint_data["text_ar"]
          cit.guidance = checkpoint_data["guidance_ar"]
        end
      end
    end
  end
end
