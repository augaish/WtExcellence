class LlmResponseProcessor
  def initialize(standard_version)
    @standard_version = standard_version
  end

  def process(json_data)
    model_data = json_data["model"]
    criteria_data = model_data["criteria"] || []

    Rails.logger.info "Processing #{criteria_data.length} criteria for standard version #{@standard_version.id}"

    criteria_data.each_with_index do |criterion_data, criterion_index|
      # Create top-level criterion clause
      criterion_clause = create_criterion_clause(criterion_data, criterion_index)

      # Process subcriteria (can be nested for ISO 9001)
      subcriteria_data = criterion_data["subcriteria"] || []
      subcriteria_data.each_with_index do |subcriterion_data, subcriterion_index|
        subcriterion_clause = create_subcriterion_clause(
          criterion_clause,
          subcriterion_data,
          subcriterion_index
        )

        # Check if this subcriterion has nested subcriteria (ISO 9001: "1.1.1" under "1.1")
        nested_subcriteria = subcriterion_data["subcriteria"] || []
        if nested_subcriteria.any?
          # Process nested subcriteria recursively
          nested_subcriteria.each_with_index do |nested_subcriterion_data, nested_index|
            nested_clause = create_subcriterion_clause(
              subcriterion_clause,
              nested_subcriterion_data,
              nested_index
            )

            # Process checkpoints for nested subcriterion
            checkpoints_data = nested_subcriterion_data["checkpoints"] || []
            process_checkpoints(nested_clause, checkpoints_data)
          end
        else
          # No nested subcriteria, process checkpoints directly under this subcriterion
          checkpoints_data = subcriterion_data["checkpoints"] || []
          process_checkpoints(subcriterion_clause, checkpoints_data)
        end
      end
    end
  end

  private

  def create_criterion_clause(criterion_data, index)
    code = criterion_data["id"].to_s

    clause = Clause.find_or_create_by(
      standard_version: @standard_version,
      code: code
    ) do |c|
      c.parent = nil # Top-level criteria have no parent
      c.sort_order = index
      c.stable_key = "criterion_#{code}"
    end

    # Update translations
    update_clause_translations(clause, criterion_data)

    clause
  end

  def create_subcriterion_clause(parent_clause, subcriterion_data, index)
    code = subcriterion_data["id"].to_s

    clause = Clause.find_or_create_by(
      standard_version: @standard_version,
      code: code
    ) do |c|
      c.parent = parent_clause
      c.sort_order = index
      # Handle both dashes (KAQA) and dots (ISO 9001) in stable_key
      normalized_code = code.gsub("-", "_").gsub(".", "_")
      c.stable_key = "subcriterion_#{normalized_code}"
    end

    # Update parent if it changed
    clause.update(parent: parent_clause) if clause.parent != parent_clause

    # Update translations
    update_clause_translations(clause, subcriterion_data)

    clause
  end

  def update_clause_translations(clause, data)
    # English translation
    if data["name_en"].present?
      translation = ClauseTranslation.find_or_initialize_by(
        clause: clause,
        language_code: "en"
      )
      translation.title = data["name_en"]
      translation.summary = data["name_en"] # Use name as summary for now
      translation.body = data["name_en"] # Use name as body for now
      translation.save!
    end

    # Arabic translation
    if data["name_ar"].present?
      translation = ClauseTranslation.find_or_initialize_by(
        clause: clause,
        language_code: "ar"
      )
      translation.title = data["name_ar"]
      translation.summary = data["name_ar"] # Use name as summary for now
      translation.body = data["name_ar"] # Use name as body for now
      translation.save!
    end
  end

  def process_checkpoints(clause, checkpoints_data)
    Rails.logger.info "Processing #{checkpoints_data.length} checkpoints for clause #{clause.code}"

    checkpoints_data.each_with_index do |checkpoint_data, index|
      code = checkpoint_data["id"].to_s

      checklist_item = ChecklistItem.find_or_create_by(
        clause: clause,
        code: code
      ) do |ci|
        ci.item_type = "requirement"
        ci.sort_order = index
        ci.stable_key = "checkpoint_#{code.gsub('-', '_')}"
      end

      # Update translations
      update_checkpoint_translations(checklist_item, checkpoint_data)
    end
  end

  def update_checkpoint_translations(checklist_item, data)
    # English translation
    if data["text_en"].present?
      translation = ChecklistItemTranslation.find_or_initialize_by(
        checklist_item: checklist_item,
        language_code: "en"
      )
      translation.text = data["text_en"]
      translation.guidance = nil # New format doesn't have guidance
      translation.save!
    end

    # Arabic translation
    if data["text_ar"].present?
      translation = ChecklistItemTranslation.find_or_initialize_by(
        checklist_item: checklist_item,
        language_code: "ar"
      )
      translation.text = data["text_ar"]
      translation.guidance = nil # New format doesn't have guidance
      translation.save!
    end
  end
end
