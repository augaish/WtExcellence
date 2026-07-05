class SearchController < ApplicationController
  private

  def current_company
    return @current_company if defined?(@current_company)
    company_user = current_user&.company_user
    @current_company = company_user&.company
  end

  def format_standard_result(standard, formatted_results, seen_checkpoint_ids)
    # When searching for a standard, return all checkpoints from all its clauses
    standard_version = standard.standard_versions.order(created_at: :desc).first
    return unless standard_version

    clauses = standard_version.clauses.includes(:checklist_items, :standard_version)
    clauses.each do |clause|
      checkpoints = clause.checklist_items.includes(:clause).order(:sort_order)
      checkpoints.each do |checkpoint|
        next if seen_checkpoint_ids[checkpoint.id]
        seen_checkpoint_ids[checkpoint.id] = true

        formatted_results << format_checkpoint_hash(
          checkpoint: checkpoint,
          clause: clause,
          standard: standard
        )
      end
    end
  end

  def format_clause_result(clause, formatted_results, seen_checkpoint_ids)
    standard = clause.standard_version&.standard
    # When searching for a clause, return all its checkpoints
    checkpoints = clause.checklist_items.includes(:clause).order(:sort_order)

    return unless checkpoints.any?

    checkpoints.each do |checkpoint|
      next if seen_checkpoint_ids[checkpoint.id]
      seen_checkpoint_ids[checkpoint.id] = true

      formatted_results << format_checkpoint_hash(
        checkpoint: checkpoint,
        clause: clause,
        standard: standard
      )
    end
  end

  def format_checklist_item_result(checklist_item, formatted_results, seen_checkpoint_ids)
    # Skip if we've already seen this checkpoint
    return if seen_checkpoint_ids[checklist_item.id]
    seen_checkpoint_ids[checklist_item.id] = true

    clause = checklist_item.clause
    standard = clause&.standard_version&.standard

    formatted_results << format_checkpoint_hash(
      checkpoint: checklist_item,
      clause: clause,
      standard: standard
    )
  end

  def format_checkpoint_hash(checkpoint:, clause:, standard:)
    {
      id: checkpoint.id,
      type: "Checkpoint",
      code: checkpoint.code,
      name: checkpoint.text("en"),
      description: checkpoint.guidance("en"),
      standard_name: standard&.display_name("en") || standard&.code,
      clause_code: clause&.full_code,
      clause_name: clause&.title("en"),
      clause_id: clause&.id,
      is_sub_clause: clause&.parent.present?
    }
  end

  def format_capa_result(capa, formatted_results, seen_checkpoint_ids)
    formatted_results << {
      id: capa.id,
      friendly_id: capa.friendly_id,
      friendly_code: capa.friendly_code,
      type: "Capa",
      name: capa.title,
      description: capa.description
    }
  end

  def format_upload_result(upload, formatted_results)
    formatted_results << {
      id: upload.id,
      type: "Upload",
      name: upload.display_name,
      description: upload.notes,
      folder_id: upload.folder_id
    }
  end

  public

  def index
    query = params[:q] || params[:search]

    if query.blank?
      if request.format.json?
        render json: { results: [] }
      else
        @search = query
        @results = []
      end
      return
    end

    if current_company.nil?
      if request.format.json?
        return render json: { results: [] }
      else
        @search = query
        @results = []
        return
      end
    end

    standards_results = PgSearch.multisearch(query)
      .where(searchable_type: "Standard")
      .joins("INNER JOIN company_standards ON company_standards.standard_id::text = pg_search_documents.searchable_id::text")
      .where(company_standards: { company_id: current_company.id })
      .limit(5)

    clauses_results = PgSearch.multisearch(query)
      .where(searchable_type: "Clause")
      .joins("INNER JOIN clauses ON clauses.id::text = pg_search_documents.searchable_id::text")
      .joins("INNER JOIN standard_versions ON standard_versions.id::text = clauses.standard_version_id::text")
      .joins("INNER JOIN standards ON standards.id::text = standard_versions.standard_id::text")
      .joins("INNER JOIN company_standards ON company_standards.standard_id::text = standards.id::text")
      .where(company_standards: { company_id: current_company.id })
      .limit(5)

    checklist_items_results = PgSearch.multisearch(query)
      .where(searchable_type: "ChecklistItem")
      .joins("INNER JOIN checklist_items ON checklist_items.id::text = pg_search_documents.searchable_id::text")
      .joins("INNER JOIN clauses ON clauses.id::text = checklist_items.clause_id::text")
      .joins("INNER JOIN standard_versions ON standard_versions.id::text = clauses.standard_version_id::text")
      .joins("INNER JOIN standards ON standards.id::text = standard_versions.standard_id::text")
      .joins("INNER JOIN company_standards ON company_standards.standard_id::text = standards.id::text")
      .where(company_standards: { company_id: current_company.id })
      .limit(5)


    capas_results = PgSearch.multisearch(query)
      .where(searchable_type: "Capa")
      .joins("INNER JOIN capas ON capas.id::text = pg_search_documents.searchable_id::text")
      .where(capas: { company_id: current_company.id })
      .limit(5)

    uploads_results = PgSearch.multisearch(query)
      .where(searchable_type: "Upload")
      .joins("INNER JOIN uploads ON uploads.id::text = pg_search_documents.searchable_id::text")
      .where(uploads: { company_id: current_company.id })
      .limit(5)

    # Combine results - convert to arrays and combine
    results = standards_results.to_a + clauses_results.to_a + checklist_items_results.to_a + capas_results.to_a + uploads_results.to_a


    if request.format.json?
      # Format results for API response
      formatted_results = []
      # Track checkpoint IDs to avoid duplicates (using hash for O(1) lookups)
      seen_checkpoint_ids = {}

      results.each do |result|
        searchable = result.searchable
        next unless searchable

        case searchable.class.name
        when "Standard"
          format_standard_result(searchable, formatted_results, seen_checkpoint_ids)
        when "Clause"
          format_clause_result(searchable, formatted_results, seen_checkpoint_ids)
        when "ChecklistItem"
          format_checklist_item_result(searchable, formatted_results, seen_checkpoint_ids)
        when "Capa"
          format_capa_result(searchable, formatted_results, seen_checkpoint_ids)
        when "Upload"
          # Respect per-upload visibility so private uploads owned by other
          # company members are never surfaced through search.
          format_upload_result(searchable, formatted_results) if searchable.visible_to_user?(current_user)
        end
      end

      render json: { results: formatted_results }
    else
      @search = query
      @results = results
    end
  end

  def clauses
    query = params[:q] || params[:search]

    if query.blank?
      render json: { results: [] }
      return
    end

    if current_company.nil?
      render json: { results: [] }
      return
    end

    # Only return clauses from standards linked to the current company (same scoping as index)
    standard_results = PgSearch.multisearch(query)
      .where(searchable_type: "Standard")
      .joins("INNER JOIN company_standards ON company_standards.standard_id::text = pg_search_documents.searchable_id::text")
      .where(company_standards: { company_id: current_company.id })

    clause_results = PgSearch.multisearch(query)
      .where(searchable_type: "Clause")
      .joins("INNER JOIN clauses ON clauses.id::text = pg_search_documents.searchable_id::text")
      .joins("INNER JOIN standard_versions ON standard_versions.id::text = clauses.standard_version_id::text")
      .joins("INNER JOIN standards ON standards.id::text = standard_versions.standard_id::text")
      .joins("INNER JOIN company_standards ON company_standards.standard_id::text = standards.id::text")
      .where(company_standards: { company_id: current_company.id })

    results = standard_results.to_a + clause_results.to_a

    # Format results for API response - only return Clauses
    formatted_results = []
    seen_clause_ids = {}

    results.each do |result|
      searchable = result.searchable
      next unless searchable

      case searchable.class.name
      when "Standard"
        # When searching for a standard, return all its clauses (standard already scoped to company)
        standard_version = searchable.standard_versions.order(created_at: :desc).first
        if standard_version
          clauses = standard_version.clauses.includes(:standard_version, :parent)
          clauses.each do |clause|
            next if seen_clause_ids[clause.id]
            seen_clause_ids[clause.id] = true

            standard = clause.standard_version&.standard
            formatted_results << {
              id: clause.id,
              type: clause.parent.present? ? "Sub-Clause" : "Clause",
              code: clause.code,
              title: clause.title("en"),
              standard_name: standard&.display_name("en") || standard&.code,
              is_sub_clause: clause.parent.present?
            }
          end
        end
      when "Clause"
        # Skip if we've already seen this clause
        next if seen_clause_ids[searchable.id]
        seen_clause_ids[searchable.id] = true

        standard = searchable.standard_version&.standard
        formatted_results << {
          id: searchable.id,
          type: searchable.parent.present? ? "Sub-Clause" : "Clause",
          code: searchable.code,
          title: searchable.title("en"),
          standard_name: standard&.display_name("en") || standard&.code,
          is_sub_clause: searchable.parent.present?
        }
      end
    end

    render json: { results: formatted_results }
  end
end
