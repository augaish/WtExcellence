class StandardsController < Dashboard::BaseController
  before_action :require_platform_admin, only: [
    :upload_standard,
    :edit,
    :create_clause,
    :update_clause,
    :destroy_clause,
    :create_checkpoint,
    :destroy_checkpoint,
    :update_checkpoint,
    :move_checkpoint,
    :reorder_clause,
    :move_clause,
    :mark_clause_reviewed,
    :mark_checkpoint_reviewed,
    :update_clause_points,
    :distribute_weights,
    :rollup_weights,
    :new_version,
    :create_version,
    :publish_version
  ]

  def index
    # Start with base query
    @standards = Standard.includes(:standard_versions, :standard_translations, :ingestion_jobs)
                         .order(created_at: :desc)

    # Filter by company if user is not super_admin or delegated_admin
    unless current_user&.super_admin? || current_user&.delegated_admin?
      # Get user's company (users belong to exactly one company)
      company = current_user&.company

      if company
        # Only show standards assigned to the user's company
        @standards = @standards.joins(:company_standards)
                               .where(company_standards: { company_id: company.id, status: "active" })
                               .distinct
      else
        # User has no company, show no standards
        @standards = Standard.none
      end
    end

    # Filter by status if provided
    status_filter = params[:status]
    if status_filter.present? && status_filter != "all"
      @standards = @standards.joins(:standard_versions)
                             .where(standard_versions: { status: status_filter })
                             .distinct
    end

    # Search functionality
    if params[:search].present?
      search_term = params[:search].downcase
      @standards = @standards.where("LOWER(code) ILIKE ?", "%#{search_term}%")
    end

    # Get statistics for each standard
    @standards_with_stats = @standards.map do |standard|
      latest_version = standard.latest_version

      # Check if there's an active ingestion job (queued or processing)
      active_job = standard.ingestion_jobs
                           .where(status: [ "queued", "processing" ])
                           .order(created_at: :desc)
                           .first

      if latest_version
        clause_count = latest_version.clauses.count
        checklist_count = latest_version.clauses.joins(:checklist_items).count
        subclause_count = latest_version.clauses.where.not(parent_id: nil).count

        # Compliance numbers are loaded asynchronously by the client (see
        # `standards_compliance` JSON action) so the list doesn't block on
        # per-standard score calculation. We still expose `company_count` for
        # super admins because it's a cheap COUNT query.
        company_count = if current_user&.super_admin? || current_user&.delegated_admin?
          standard.company_standards.where(status: "active").count
        else
          nil
        end

        {
          standard: standard,
          latest_version: latest_version,
          clause_count: clause_count,
          checklist_count: checklist_count,
          subclause_count: subclause_count,
          compliance_percentage: nil,
          tool_compliance_data: [],
          company_count: company_count,
          average_company_compliance: nil,
          is_processing: active_job.present? && standard.standard_versions.count <= 1 || (clause_count == 0 && standard.ingestion_jobs.where(status: [ "queued", "processing" ]).exists?)
        }
      else
        {
          standard: standard,
          latest_version: nil,
          clause_count: 0,
          checklist_count: 0,
          subclause_count: 0,
          compliance_percentage: 0,
          tool_compliance_data: [],
          company_count: nil,
          average_company_compliance: nil,
          is_processing: active_job.present?
        }
      end
    end
  end

  # JSON — per-standard compliance for all standards visible to the current user.
  # Used by the cards on the standards index to fill in the compliance
  # section after the initial (cheap) render.
  def standards_compliance
    scope = Standard.all
    unless current_user&.super_admin? || current_user&.delegated_admin?
      company = current_user&.company
      if company
        scope = scope.joins(:company_standards)
                     .where(company_standards: { company_id: company.id, status: "active" })
                     .distinct
      else
        scope = Standard.none
      end
    end

    ids = Array(params[:ids]).map(&:to_s).reject(&:blank?)
    scope = scope.where(id: ids) if ids.any?

    result = scope.includes(:standard_versions).each_with_object({}) do |standard, acc|
      latest = standard.latest_version
      unless latest
        acc[standard.id] = { compliance_percentage: 0, average_company_compliance: nil }
        next
      end

      if current_user&.super_admin? || current_user&.delegated_admin?
        cs_scope = CompanyStandard.active.where(standard_id: standard.id)
        cs_scope.where(cached_compliance_percentage: nil).each(&:refresh_compliance_cache!)
        average = cs_scope.average(:cached_compliance_percentage).to_f.round(2)
        acc[standard.id] = {
          compliance_percentage: average,
          average_company_compliance: average,
          company_count: cs_scope.count
        }
      else
        cs = CompanyStandard.find_by(standard_id: standard.id, company_id: current_company&.id)
        compliance = cs ? cs.compliance_percentage.round(2) : 0
        acc[standard.id] = {
          compliance_percentage: compliance,
          tool_compliance_data: [] # per-tool breakdown removed from fast path
        }
      end
    end

    render json: { compliance: result }
  end

  def calculate_compliance_percentage(standard_version)
    return 0 unless standard_version
    return 0 unless current_company.present?

    result = ClauseScoreCalculator.calculate_compliance_for_company(standard_version.standard, current_company)
    result ? result[:compliance_percentage].to_f : 0
  end

  def calculate_compliance_with_details(standard, standard_version)
    return { average_compliance: 0, tool_data: [] } unless standard_version
    return { average_compliance: 0, tool_data: [] } unless current_company.present?

    # Standard-wide compliance (correct math: Σ scored / Σ allocated × 100).
    overall = ClauseScoreCalculator.calculate_compliance_for_company(standard, current_company)
    overall_percentage = overall ? overall[:compliance_percentage].to_f : 0

    # Per-tool breakdown is still useful for the UI when a standard is split
    # across multiple tools — show each tool's contribution.
    tools = ToolClause.joins(:clause)
                      .where(clauses: { standard_version_id: standard_version.id })
                      .includes(:tool)
                      .distinct
                      .map(&:tool)
                      .uniq

    tool_data = tools.filter_map do |tool|
      r = ClauseScoreCalculator.calculate_standard_compliance(standard, tool, current_company)
      next unless r && r[:total_allocated_points].to_f > 0
      {
        tool_name: tool.name,
        compliance_percentage: r[:compliance_percentage].to_f,
        scored_points: r[:total_scored_points].to_f,
        allocated_points: r[:total_allocated_points].to_f
      }
    end

    { average_compliance: overall_percentage, tool_data: tool_data }
  end

  # Calculate company-wide statistics for super admins
  def calculate_company_wide_stats(standard, standard_version)
    return { company_count: 0, average_compliance: 0 } unless standard_version

    assigned_companies = standard.company_standards
                                 .where(status: "active")
                                 .includes(:company)
                                 .map(&:company)

    return { company_count: 0, average_compliance: 0 } if assigned_companies.empty?

    total = 0.0
    assigned_companies.each do |company|
      r = ClauseScoreCalculator.calculate_compliance_for_company(standard, company)
      total += r ? r[:compliance_percentage].to_f : 0
    end

    average_compliance = (total / assigned_companies.count).round(2)
    { company_count: assigned_companies.count, average_compliance: average_compliance }
  end


  # HTML fragment — direct children of a clause, rendered with the
  # `_clause_hierarchy.html.erb` partial. The client fetches this on first
  # expand of a node so we don't send the whole (potentially huge) tree
  # upfront. Each returned child also renders its own lazy placeholder for
  # its own children.
  def clause_children
    clause = Clause.find_by(id: params[:id])
    unless clause
      render html: "", status: :not_found
      return
    end

    standard = clause.standard_version&.standard
    unless standard && standard_accessible_to_user?(standard)
      render html: "", status: :forbidden
      return
    end

    children = if current_user&.super_admin? || current_user&.delegated_admin? ||
                  current_user&.company_user&.has_admin_privileges? ||
                  current_user&.company_user&.company_viewer?
      clause.children.ordered
    else
      visible_ids = current_user.visible_clauses_with_hierarchy.pluck(:id)
      clause.children.ordered.where(id: visible_ids)
    end

    html = children.map { |child| render_to_string(partial: "standards/clause_hierarchy", locals: { clause: child, level: child.code.count(".") }) }.join
    render html: html.html_safe, layout: false
  end

  def show
    @standard = Standard.find_by(id: params[:id])
    unless @standard
      respond_to do |format|
        format.html { redirect_to standards_path, alert: "Standard not found" }
        format.turbo_stream { redirect_to standards_path, alert: "Standard not found" }
        format.json { render json: { error: "Standard not found" }, status: :not_found }
      end
      return
    end

    unless standard_accessible_to_user?(@standard)
      respond_to do |format|
        format.html { redirect_to standards_path, alert: "You don't have access to this standard.", status: :forbidden }
        format.turbo_stream { redirect_to standards_path, alert: "You don't have access to this standard.", status: :forbidden }
        format.json { render json: { error: "You don't have access to this standard." }, status: :forbidden }
      end
      return
    end

    # Load all versions for the versions tab
    @versions = @standard.standard_versions.includes(:clauses).order(created_at: :desc)

    # Uploads available for evidence linking (company-scoped)
    company = current_company || current_user&.company
    @linkable_uploads = company ? Upload.for_company(company.id).order(:filename).limit(200) : Upload.none
    @linked_upload_ids = @standard.evidence_attachments.pluck(:upload_id)

    # Check if version_id is provided in params (for version selector)
    if params[:version_id].present?
      @selected_version = @standard.standard_versions.find(params[:version_id])
      @latest_version = @selected_version
    else
      @latest_version = @standard.latest_version
    end

    if @latest_version
      # Load clauses for the clause tree tab
      # Filter clauses based on user role
      if current_user&.super_admin? || current_user&.delegated_admin? || current_user&.company_user&.has_admin_privileges? || current_user&.company_user&.company_viewer?
        # Admins and viewers see all clauses (viewers are read-only)
        @clauses = @latest_version.clauses.includes(:clause_translations, :checklist_items, :children)
                                 .root_clauses
                                 .ordered
      else
        # Contributors and auditors only see clauses they have assignments for
        @clauses = current_user.visible_root_clauses(@latest_version)
                               .includes(:clause_translations, :checklist_items, :children)
                               .ordered
      end

      # Deep link from breadcrumbs: expand ancestor chain and scroll to the focused clause.
      if params[:focus].present?
        focus_clause = @latest_version.clauses.find_by(id: params[:focus])
        if focus_clause
          @focus_clause_id = focus_clause.id
          chain = []
          node = focus_clause.parent
          while node
            chain.unshift(node.id)
            node = node.parent
          end
          @focus_expand_chain = chain
        end
      end

      # Allow breadcrumbs to force a tab without focusing a specific clause.
      allowed_tabs = %w[versions clause-tree assignees]
      @initial_tab = params[:tab] if allowed_tabs.include?(params[:tab])
      @initial_tab ||= "clause-tree" if @focus_clause_id

      # Get statistics
      @clause_count = @latest_version.clauses.count
      @checklist_count = @latest_version.clauses.joins(:checklist_items).count
      @subclause_count = @latest_version.clauses.where.not(parent_id: nil).count
      @compliance_percentage = if current_company
        cs = CompanyStandard.find_by(standard_id: @standard.id, company_id: current_company.id)
        cs ? cs.compliance_percentage.round(2) : 0
      else
        0
      end
    end

    # Load company standards (companies that have this standard assigned)
    # Viewers should only see their own company's assignment
    if viewer?
      # Viewers only see their company's assignment
      @company_standards = @standard.company_standards
                                    .where(company_id: current_company&.id)
                                    .includes(:company, :active_version)
                                    .order(:created_at)
    else
      # Super admins and delegated admins see all company assignments
      @company_standards = @standard.company_standards
                                    .includes(:company, :active_version)
                                    .order(:created_at)
    end

    # Calculate compliance for each company
    @company_compliance = {}
    if @latest_version
      @company_standards.each do |company_standard|
        company = company_standard.company
        result = ClauseScoreCalculator.calculate_compliance_for_company(@standard, company)
        @company_compliance[company.id] = result ? result[:compliance_percentage].to_f : 0
      end
    end

    # Get users from current company for assignment (if company admin)
    if current_company && current_user&.company_user&.has_admin_privileges?
      @company_users = current_company.company_users.includes(:user).order("users.name")
    else
      @company_users = CompanyUser.none
    end
  end

  def versions
    @standard = Standard.find_by(id: params[:id])
    unless @standard
      render json: { error: "Standard not found" }, status: :not_found
      return
    end
    unless standard_accessible_to_user?(@standard)
      render json: { error: "You don't have access to this standard." }, status: :forbidden
      return
    end

    latest_version = @standard.latest_version
    versions = @standard.standard_versions.published.order(created_at: :desc).map do |version|
      {
        id: version.id,
        version_label: version.version_label,
        status: version.status,
        is_latest: version.id == latest_version&.id
      }
    end

    render json: { versions: versions }
  end

  def available_companies
    unless current_user&.can_assign_standards_to_companies?
      render json: { error: "You don't have permission to assign standards to companies." }, status: :forbidden
      return
    end

    @standard = Standard.find_by(id: params[:id])
    version = StandardVersion.find_by(id: params[:version_id], standard_id: @standard&.id)

    unless @standard && version
      render json: { error: "Standard or version not found" }, status: :not_found
      return
    end
    unless standard_accessible_to_user?(@standard)
      render json: { error: "You don't have access to this standard." }, status: :forbidden
      return
    end

    # Get all companies (including pending ones for super admins to set up)
    all_companies = Company.all.order(:name)

    # Get companies that already have this version assigned
    companies_with_version = CompanyStandard.where(
      standard_id: @standard.id,
      active_version_id: version.id
    ).pluck(:company_id)

    # Filter out companies that already have this version
    available_companies = all_companies.reject { |c| companies_with_version.include?(c.id) }

    companies_data = available_companies.map do |company|
      {
        id: company.id,
        name: company.name
      }
    end

    render json: { companies: companies_data }
  end

  def assign
    unless current_user&.can_assign_standards_to_companies?
      redirect_to standards_path, alert: "You don't have permission to assign standards to companies."
      return
    end

    @standard = Standard.find_by(id: params[:id])
    version = StandardVersion.find_by(id: params[:version_id], standard_id: @standard&.id)
    company_ids = params[:company_ids] || []

    unless @standard && version
      redirect_to standards_path, alert: "Standard or version not found"
      return
    end

    if company_ids.empty?
      redirect_to standards_path, alert: "Please select at least one company"
      return
    end

    begin
      company_ids.each do |company_id|
        company = Company.find_by(id: company_id)
        next unless company

        # Find or create company_standard record
        company_standard = CompanyStandard.find_or_initialize_by(
          company_id: company.id,
          standard_id: @standard.id
        )

        # If it's a new assignment or version change, record history
        if company_standard.new_record?
          company_standard.assign_attributes(
            status: "active",
            active_version_id: version.id,
            assigned_by: current_user.id,
            assigned_at: Time.current
          )
          company_standard.save!
        elsif company_standard.active_version_id != version.id
          # Record version change in history
          company_standard.change_version(version.id, current_user.id, "Assigned version #{version.version_label}")
        end
      end

      flash[:notice] = "Standard version #{version.version_label} has been assigned successfully!"
      redirect_to standard_path(@standard)
    rescue => e
      Rails.logger.error "Assign standard error: #{e.message}"
      redirect_to standards_path, alert: "Failed to assign standard: #{e.message}"
    end
  end

  def compare
    @standard = Standard.find_by(id: params[:id])
    unless @standard
      redirect_to standards_path, alert: "Standard not found"
      return
    end
    unless standard_accessible_to_user?(@standard)
      redirect_to standards_path, alert: "You don't have access to this standard.", status: :forbidden
      return
    end

    # Get both versions from params
    # version_id is the "new" version (right side)
    # compare_with is the "old" version (left side)
    new_version_id = params[:version_id] || params[:new_version_id]
    old_version_id = params[:compare_with] || params[:old_version_id]

    # If no versions specified, default to latest vs previous
    if new_version_id.blank? && old_version_id.blank?
      latest = @standard.latest_version
      previous = @standard.standard_versions.order(created_at: :desc).offset(1).first

      if latest && previous
        new_version_id = latest.id
        old_version_id = previous.id
      elsif latest
        redirect_to standard_path(@standard), alert: "Need at least two versions to compare"
        return
      else
        redirect_to standard_path(@standard), alert: "No versions found"
        return
      end
    end

    # Get new version (right side)
    if new_version_id.present?
      @current_version = @standard.standard_versions.find_by(id: new_version_id)
    else
      @current_version = @standard.latest_version
    end

    unless @current_version
      redirect_to standard_path(@standard), alert: "New version not found"
      return
    end

    # Get old version (left side)
    if old_version_id.present?
      @compare_version = @standard.standard_versions.find_by(id: old_version_id)
    else
      # If old version not specified, use the previous version
      @compare_version = @standard.standard_versions
                                 .where("created_at < ?", @current_version.created_at)
                                 .order(created_at: :desc)
                                 .first
    end

    unless @compare_version
      redirect_to standard_path(@standard), alert: "Old version not found"
      return
    end

    # Can't compare a version with itself
    if @current_version.id == @compare_version.id
      redirect_to standard_path(@standard), alert: "Cannot compare a version with itself"
      return
    end

    # Generate diff (new version vs old version)
    comparator = StandardVersionComparator.new(@current_version, @compare_version)
    @diff = comparator.generate_diff

    # Get all available versions for both dropdowns
    @available_versions = @standard.standard_versions.order(created_at: :desc)

    # Store version IDs for the view
    @current_version_id = @current_version.id
    @compare_version_id = @compare_version.id
  end

  def edit
    @standard = Standard.find_by(id: params[:id])

    unless @standard
      redirect_to standards_path, alert: "Standard not found"
      return
    end

    # Get version from params or default to latest
    if params[:version_id].present?
      @version = StandardVersion.find_by(id: params[:version_id], standard_id: @standard.id)
      unless @version
        redirect_to standard_path(@standard), alert: "Version not found"
        return
      end
    else
      @version = @standard.latest_version
    end

    if @version
      @clauses = @version.clauses.includes(:clause_translations, :checklist_items, :children)
                              .root_clauses
                              .ordered
    end

    # Load companies for publish version dialog (including pending for super admins to set up)
    @companies = Company.all.order(:name)
    @assigned_companies = @standard.company_standards.includes(:company).map(&:company) if @standard
  end

  def create_clause
    # Handle root clause creation (when no parent_id is provided)
    if params[:parent_id].blank?
      # For root clauses, we need standard_version_id
      unless params[:standard_version_id].present?
        respond_to do |format|
          format.json { render json: { error: "Standard version ID is required for root clauses" }, status: :unprocessable_entity }
        end
        return
      end

      standard_version = StandardVersion.find(params[:standard_version_id])

      # Calculate the next code and sort_order for the new root clause
      existing_root_clauses = standard_version.clauses.root_clauses.ordered
      next_sort_order = existing_root_clauses.maximum(:sort_order).to_i + 1
      next_code = (existing_root_clauses.count + 1).to_s

      clause = Clause.new(
        standard_version_id: standard_version.id,
        parent_id: nil,
        code: next_code,
        sort_order: next_sort_order
      )
    else
      # Handle sub-clause creation (existing logic)
      parent_clause = Clause.find(params[:parent_id])

      # Calculate the next code and sort_order for the new clause
      existing_children = parent_clause.children.ordered
      next_sort_order = existing_children.maximum(:sort_order).to_i + 1
      next_code = "#{parent_clause.code}.#{existing_children.count + 1}"

      clause = Clause.new(
        standard_version_id: parent_clause.standard_version_id,
        parent_id: parent_clause.id,
        code: next_code,
        sort_order: next_sort_order
      )
    end

    if clause.save
      current_locale = I18n.locale.to_s
      title = params[:title] || "New Clause"

      # Create translation in current locale
      translation = clause.clause_translations.create!(
        language_code: current_locale,
        title: title,
        summary: "",
        body: "",
        needs_review: false
      )

      # Auto-translate to all other available languages
      translate_clause_to_other_languages(clause, current_locale, title)

      respond_to do |format|
        format.json {
          # Calculate level based on code depth (number of dots)
          level = clause.code.count(".")
          # Render the partial and return HTML
          html = render_to_string(
            partial: "clause_hierarchy_edit",
            locals: { clause: clause, level: level },
            formats: [ :html ]
          )
          render json: {
            message: "Clause created successfully",
            html: html,
            clause_id: clause.id,
            translation_id: translation.id
          }, status: :ok
        }
      end
    else
      respond_to do |format|
        format.json { render json: { error: clause.errors.full_messages.join(", ") }, status: :unprocessable_entity }
      end
    end
  rescue => e
    respond_to do |format|
      format.json { render json: { error: e.message }, status: :unprocessable_entity }
    end
  end

  def update_clause
    clause = Clause.find(params[:clause_id])
    current_locale = I18n.locale.to_s

    # Update the translation in current locale (or create if it doesn't exist)
    translation = clause.clause_translations.find_or_initialize_by(language_code: current_locale)
    translation.title = params[:title] if params[:title].present?
    translation.summary = params[:summary] if params[:summary].present?
    translation.body = params[:body] if params[:body].present?

    if translation.save
      # Check which translations need review
      translations_needing_review = clause.clause_translations
        .where(needs_review: true)
        .where.not(language_code: current_locale)
        .pluck(:language_code)

      respond_to do |format|
        format.json {
          render json: {
            message: "Clause updated successfully",
            clause: {
              id: clause.id,
              code: clause.code,
              title: clause.title(current_locale)
            },
            translation_id: translation.id,
            translations_need_review: translations_needing_review.any?,
            languages_needing_review: translations_needing_review,
            needs_review_in_other_languages: translations_needing_review.any?
          }, status: :ok
        }
      end
    else
      respond_to do |format|
        format.json { render json: { error: translation.errors.full_messages.join(", ") }, status: :unprocessable_entity }
      end
    end
  rescue => e
    respond_to do |format|
      format.json { render json: { error: e.message }, status: :unprocessable_entity }
    end
  end

  def destroy_clause
    clause = Clause.find(params[:clause_id])

    # Store info before deletion
    parent_id = clause.parent_id
    parent = clause.parent
    standard_version = clause.standard_version

    # Invalidate score caches on ancestors before deletion
    standard = standard_version&.standard
    if standard && parent
      ClauseScorePropagator.invalidate_cache_for_tool_clause_changes(standard, [ parent ])
    elsif standard
      ClauseScorePropagator.invalidate_cache_for_tool_clause_changes(standard, [ clause ])
    end

    # This will also delete children due to dependent: :destroy
    clause.destroy

    # Recalculate codes for remaining siblings
    updated_codes = {}
    if parent_id.present? && parent
      # Reload parent to ensure it's fresh
      parent.reload
      # Recalculate codes for remaining siblings under the same parent
      recalculate_all_sibling_codes(parent, updated_codes)
    else
      # Recalculate codes for remaining root clauses
      standard_version.reload
      standard_version.clauses.root_clauses.ordered.each_with_index do |root_clause, index|
        new_code = "#{index + 1}"
        root_clause.update_columns(code: new_code, sort_order: index)
        updated_codes[root_clause.id] = new_code
        # Update all descendants
        update_all_descendant_codes(root_clause, updated_codes) if root_clause.children.any?
      end
    end

    respond_to do |format|
      format.json {
        render json: {
          message: "Clause deleted successfully",
          updated_codes: updated_codes
        }, status: :ok
      }
    end
  rescue => e
    respond_to do |format|
      format.json { render json: { error: e.message }, status: :unprocessable_entity }
    end
  end

  def create_checkpoint
    Rails.logger.info "create_checkpoint called with params: #{params.inspect}"

    unless params[:clause_id].present?
      respond_to do |format|
        format.json { render json: { error: "Clause ID is required" }, status: :unprocessable_entity }
      end
      return
    end

    clause = Clause.find(params[:clause_id])

    # Calculate the next sort_order for the new checkpoint
    next_sort_order = clause.checklist_items.maximum(:sort_order).to_i + 1

    checkpoint = clause.checklist_items.new(
      item_type: "requirement",
      sort_order: next_sort_order
    )

    Rails.logger.info "Checkpoint before save: #{checkpoint.inspect}"
    Rails.logger.info "Checkpoint valid?: #{checkpoint.valid?}"
    Rails.logger.info "Checkpoint errors: #{checkpoint.errors.full_messages}" unless checkpoint.valid?

    if checkpoint.save
      current_locale = I18n.locale.to_s
      text = params[:text].present? ? params[:text].strip : "New checkpoint"

      # Ensure text is not empty (validation requirement)
      text = "New checkpoint" if text.blank?

      Rails.logger.info "Creating translation with locale: #{current_locale}, text: #{text[0..50]}"

      # Verify language exists
      language = Language.find_by(code: current_locale)
      unless language
        Rails.logger.error "Language with code '#{current_locale}' does not exist!"
        checkpoint.destroy # Rollback the checkpoint creation
        respond_to do |format|
          format.json { render json: { error: "Language '#{current_locale}' is not configured. Please ensure languages are seeded." }, status: :unprocessable_entity }
        end
        return
      end

      # Create translation in current locale using create! directly
      begin
        translation = checkpoint.checklist_item_translations.create!(
          language_code: current_locale,
          text: text,
          needs_review: false
        )
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error "Translation creation failed: #{e.message}"
        checkpoint.destroy # Rollback the checkpoint creation
        respond_to do |format|
          format.json { render json: { error: "Translation creation failed: #{e.message}" }, status: :unprocessable_entity }
        end
        return
      end

      # Auto-translate to other languages if user provided real content (not default placeholder)
      default_texts = [ "New checkpoint", "[Translation needed]" ]
      is_real_content = text.present? && !default_texts.include?(text.strip)

      if is_real_content
        translate_checkpoint_to_other_languages(checkpoint, current_locale, text)
      end

      # Check which translations need review
      translations_needing_review = checkpoint.checklist_item_translations
        .where(needs_review: true)
        .where.not(language_code: current_locale)
        .pluck(:language_code)

      respond_to do |format|
        format.json {
          render json: {
            message: "Checkpoint created successfully",
            checkpoint: {
              id: checkpoint.id,
              text: checkpoint.text,
              clause_id: checkpoint.clause_id
            },
            translation_id: translation.id,
            translations_need_review: translations_needing_review.any?,
            languages_needing_review: translations_needing_review,
            needs_review_in_other_languages: translations_needing_review.any?
          }, status: :ok
        }
      end
    else
      Rails.logger.error "Checkpoint save failed: #{checkpoint.errors.full_messages.join(", ")}"
      respond_to do |format|
        format.json {
          render json: {
            error: checkpoint.errors.full_messages.join(", "),
            errors: checkpoint.errors.full_messages,
            checkpoint_attributes: checkpoint.attributes
          }, status: :unprocessable_entity
        }
      end
    end
  rescue => e
    Rails.logger.error "Exception in create_checkpoint: #{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    respond_to do |format|
      format.json { render json: { error: e.message, class: e.class.name }, status: :unprocessable_entity }
    end
  end

  def destroy_checkpoint
    checklist_item = ChecklistItem.find(params[:checkpoint_id])
    checklist_item.destroy

    respond_to do |format|
      format.json { render json: { message: "Checkpoint deleted successfully" }, status: :ok }
    end
  rescue => e
    respond_to do |format|
      format.json { render json: { error: e.message }, status: :unprocessable_entity }
    end
  end

  def update_checkpoint
    checklist_item = ChecklistItem.find(params[:checkpoint_id])
    current_locale = I18n.locale.to_s

    # Update the translation in current locale (or create if it doesn't exist)
    translation = checklist_item.checklist_item_translations.find_or_initialize_by(language_code: current_locale)
    old_text = translation.text || ""
    was_new_record = translation.new_record?
    translation.text = params[:text]
    translation.guidance = params[:guidance] if params[:guidance].present?

    if translation.save
      # Check if this is the first time saving real content (not default placeholder)
      # and if translations for other languages don't exist yet
      default_texts = [ "New checkpoint", "[Translation needed]" ]
      is_real_content = params[:text].present? && !default_texts.include?(params[:text].strip)
      text_changed = was_new_record || (old_text != params[:text])

      # Get existing translations for other languages
      available_locales = I18n.available_locales.map(&:to_s)
      other_locales = available_locales - [ current_locale ]
      existing_translations = checklist_item.checklist_item_translations
        .where(language_code: other_locales)
        .pluck(:language_code)

      # Auto-translate to other languages if:
      # 1. User saved real content (not default placeholder)
      # 2. Text actually changed
      # 3. Translations for other languages don't exist yet
      if is_real_content && text_changed && existing_translations.empty?
        translate_checkpoint_to_other_languages(checklist_item, current_locale, params[:text])
      end

      # Check which translations need review
      translations_needing_review = checklist_item.checklist_item_translations
        .where(needs_review: true)
        .where.not(language_code: current_locale)
        .pluck(:language_code)

      respond_to do |format|
        format.json {
          render json: {
            message: "Checkpoint updated successfully",
            translation_id: translation.id,
            translations_need_review: translations_needing_review.any?,
            languages_needing_review: translations_needing_review,
            needs_review_in_other_languages: translations_needing_review.any?
          }, status: :ok
        }
      end
    else
      respond_to do |format|
        format.json { render json: { error: translation.errors.full_messages.join(", ") }, status: :unprocessable_entity }
      end
    end
  rescue => e
    respond_to do |format|
      format.json { render json: { error: e.message }, status: :unprocessable_entity }
    end
  end

  def move_checkpoint
    checkpoint = ChecklistItem.find(params[:checkpoint_id])

    # Check if moving to a different checkpoint or to a clause
    if params[:target_checkpoint_id].present?
      target_checkpoint = ChecklistItem.find(params[:target_checkpoint_id])
      target_clause = target_checkpoint.clause
    elsif params[:target_clause_id].present?
      target_clause = Clause.find(params[:target_clause_id])
      target_checkpoint = nil
    else
      respond_to do |format|
        format.json { render json: { error: "Target checkpoint or clause required" }, status: :unprocessable_entity }
      end
      return
    end

    ActiveRecord::Base.transaction do
      old_clause_id = checkpoint.clause_id

      if target_checkpoint
        # Moving to a specific position (after target checkpoint)
        if checkpoint.clause_id == target_checkpoint.clause_id
          # Same clause - just reorder
          clause_checkpoints = checkpoint.clause.checklist_items.ordered.to_a
          dragged_index = clause_checkpoints.index(checkpoint)
          target_index = clause_checkpoints.index(target_checkpoint)

          clause_checkpoints.delete_at(dragged_index)

          if dragged_index < target_index
            target_index -= 1
          end

          clause_checkpoints.insert(target_index + 1, checkpoint)

          clause_checkpoints.each_with_index do |cp, index|
            cp.update_columns(sort_order: index)
          end
        else
          # Different clause - move to target clause after target checkpoint
          checkpoint.update_columns(clause_id: target_clause.id)

          # Get all checkpoints in target clause
          target_checkpoints = target_clause.checklist_items.ordered.to_a
          target_index = target_checkpoints.index(target_checkpoint)

          # Insert after target
          target_checkpoints.insert(target_index + 1, checkpoint)

          # Reorder target clause checkpoints
          target_checkpoints.each_with_index do |cp, index|
            cp.update_columns(sort_order: index)
          end

          # Reorder old clause checkpoints if different
          if old_clause_id != target_clause.id
            old_clause = Clause.find(old_clause_id)
            old_clause.checklist_items.ordered.each_with_index do |cp, index|
              cp.update_columns(sort_order: index)
            end
          end
        end
      else
        # Moving to a clause (append at the end)
        checkpoint.update_columns(clause_id: target_clause.id)

        # Set sort_order to be at the end
        max_sort_order = target_clause.checklist_items.maximum(:sort_order).to_i
        checkpoint.update_columns(sort_order: max_sort_order + 1)

        # Reorder old clause checkpoints if different
        if old_clause_id != target_clause.id
          old_clause = Clause.find(old_clause_id)
          old_clause.checklist_items.ordered.each_with_index do |cp, index|
            cp.update_columns(sort_order: index)
          end
        end
      end

      respond_to do |format|
        format.json {
          render json: {
            message: "Checkpoint moved successfully",
            new_clause_id: target_clause.id
          }, status: :ok
        }
      end
    end
  rescue => e
    respond_to do |format|
      format.json { render json: { error: e.message }, status: :unprocessable_entity }
    end
  end

  def reorder_clause
    clause = Clause.find(params[:clause_id])
    target_clause = Clause.find(params[:target_clause_id])
    position = params[:position] == "before" ? "before" : "after"

    # Make sure they're siblings (same parent)
    if clause.parent_id != target_clause.parent_id
      respond_to do |format|
        format.json { render json: { error: "Can only reorder clauses with the same parent" }, status: :unprocessable_entity }
      end
      return
    end

    ActiveRecord::Base.transaction do
      # Get all siblings ordered by sort_order
      parent = clause.parent
      siblings = parent ? parent.children.ordered.to_a : clause.standard_version.clauses.root_clauses.ordered.to_a

      dragged_index = siblings.index(clause)
      target_index = siblings.index(target_clause)

      # First, set all siblings to temporary codes to avoid unique constraint violations
      siblings.each do |sibling|
        set_temporary_codes(sibling)
      end

      # Remove and reinsert
      siblings.delete_at(dragged_index)

      # Adjust target index if we removed an element before it
      if dragged_index < target_index
        target_index -= 1
      end

      insert_at = position == "before" ? target_index : target_index + 1
      siblings.insert(insert_at, clause)

      # Update sort_order and codes for all siblings with final values
      updated_codes = {}
      siblings.each_with_index do |sibling, index|
        sibling.update_columns(sort_order: index)

        # Calculate new code based on position and parent
        if parent
          new_code = "#{parent.code}.#{index + 1}"
        else
          new_code = "#{index + 1}"
        end

        reset_codes(sibling, new_code, updated_codes)
      end

      respond_to do |format|
        format.json {
          render json: {
            message: "Clause reordered successfully",
            updated_codes: updated_codes
          }, status: :ok
        }
      end
    end
  rescue => e
    respond_to do |format|
      format.json { render json: { error: e.message }, status: :unprocessable_entity }
    end
  end

  def set_temporary_codes(clause)
    clause.update_columns(code: "TEMP_#{SecureRandom.hex(8)}_#{clause.code}")
    if clause.children.any?
      clause.children.each do |child|
        set_temporary_codes(child)
      end
    end
  end

  def reset_codes(clause, code, updated_codes = {})
    clause.update_columns(code: code)
    updated_codes[clause.id] = code
    if clause.children.any?
      index = 1
      clause.children.ordered.each do |child|
        reset_codes(child, "#{code}.#{index}", updated_codes)
        index += 1
      end
    end
  end

  def move_clause
    clause = Clause.find(params[:clause_id])
    new_parent_id = params[:new_parent_id]

    # Get the new parent clause (nil means moving to root level)
    new_parent = new_parent_id.present? ? Clause.find(new_parent_id) : nil

    # Check if trying to move a clause into one of its descendants
    if new_parent && is_descendant?(new_parent, clause)
      respond_to do |format|
        format.json { render json: { error: "Cannot move a clause into one of its descendants" }, status: :unprocessable_entity }
      end
      return
    end

    ActiveRecord::Base.transaction do
      old_parent_id = clause.parent_id
      old_parent = old_parent_id.present? ? Clause.find_by(id: old_parent_id) : nil

      # Store old siblings BEFORE moving the clause
      old_siblings = old_parent ? old_parent.children.ordered.to_a : clause.standard_version.clauses.root_clauses.ordered.to_a

      # Temporarily set the code to avoid unique constraint violation
      temp_code = "TEMP_#{SecureRandom.hex(8)}_#{clause.code}"

      # Set the sort_order to be at the end of the new parent's children (or root clauses)
      if new_parent
        new_sort_order = new_parent.children.maximum(:sort_order).to_i + 1
      else
        # Moving to root level
        new_sort_order = clause.standard_version.clauses.root_clauses.maximum(:sort_order).to_i + 1
      end
      clause.update_columns(code: temp_code, parent_id: new_parent_id, sort_order: new_sort_order)

      # Recalculate codes and sort_orders for all siblings in the new parent
      updated_codes = {}
      if new_parent
        recalculate_all_sibling_codes(new_parent, updated_codes)
      else
        # Recalculate root level clauses
        clause.standard_version.clauses.root_clauses.ordered.each_with_index do |root_clause, index|
          new_code = "#{index + 1}"
          root_clause.update_columns(code: new_code, sort_order: index)
          updated_codes[root_clause.id] = new_code
          # Update all descendants
          update_all_descendant_codes(root_clause, updated_codes) if root_clause.children.any?
        end
      end

      # Recalculate codes for the old siblings (excluding the moved clause)
      # This handles the renumbering of siblings left behind (e.g., 1.2 becomes 1.1)
      old_siblings.reject { |s| s.id == clause.id }.each_with_index do |sibling, index|
        if old_parent
          new_code = "#{old_parent.code}.#{index + 1}"
        else
          new_code = "#{index + 1}"
        end
        sibling.update_columns(code: new_code, sort_order: index)
        updated_codes[sibling.id] = new_code
        # Update all descendants of this sibling
        update_all_descendant_codes(sibling, updated_codes) if sibling.children.any?
      end

      # Get the new code for the moved clause
      clause.reload
      new_code = clause.code

      # Invalidate score caches on both old and new parent trees
      standard = clause.standard_version&.standard
      if standard
        roots_to_invalidate = []
        roots_to_invalidate << old_parent if old_parent
        roots_to_invalidate << new_parent if new_parent
        # If moved to/from root level, invalidate the clause itself
        roots_to_invalidate << clause if roots_to_invalidate.empty?
        ClauseScorePropagator.invalidate_cache_for_tool_clause_changes(standard, roots_to_invalidate.uniq)
      end

      respond_to do |format|
        format.json {
          render json: {
            message: "Clause moved successfully",
            new_code: new_code,
            updated_codes: updated_codes
          }, status: :ok
        }
      end
    end
  rescue => e
    respond_to do |format|
      format.json { render json: { error: e.message }, status: :unprocessable_entity }
    end
  end


  def upload_standard
    standard_name = params[:standard_name]
    pdf_file = params[:pdf_upload]

    if standard_name.blank? || pdf_file.blank?
      render json: { message: "Standard name and PDF file are required." }, status: :unprocessable_entity
      return
    end

    allowed_types = %w[application/pdf application/vnd.openxmlformats-officedocument.spreadsheetml.sheet]
    unless allowed_types.include?(pdf_file.content_type)
      render json: { message: "Only PDF and Excel (XLSX) files are allowed." }, status: :unprocessable_entity
      return
    end

    begin
      # Use current user ID (super admin)
      uploaded_by_id = current_user.id

      pipeline_type = params[:pipeline_type].to_s.strip.presence
      pipeline_type = nil unless Standard::PIPELINE_TYPES.include?(pipeline_type)

      # Create a standard record first
      standard = Standard.create!(
        code: standard_name.upcase.gsub(/[^A-Z0-9]/, "_"),
        is_primary: false,
        pipeline_type: pipeline_type
      )

      # Standard documents (PDF/XLSX) are system-level documents, not company-specific
      # Super admins upload standards without a company association
      # Non-super admins should not be able to upload standards (this action requires super_admin)
      company_id = nil

      # Save the PDF file to the uploads table (no company_id for system-level standard documents)
      upload = Upload.create_from_uploaded_file(pdf_file, uploaded_by_id, company_id: company_id)

      # Create standard version
      _standard_version = StandardVersion.create!(
        standard: standard,
        version_label: "v1.0",
        source_pdf: upload,
        status: "draft",
        notes: "Initial version"
      )

      # Create an ingestion job with queued status, linking to the standard
      ingestion_job = IngestionJob.create!(
        standard_id: standard.id,
        input_pdf_id: upload.id,
        status: "queued",
        created_by: uploaded_by_id
      )

      # Enqueue the job for background processing
      ProcessIngestionJob.perform_async(ingestion_job.id)

      # Set success message
      flash[:notice] = "Standard '#{standard_name}' uploaded successfully and is being processed"

      respond_to do |format|
        format.json do
          # Reload to get the latest_version that was just created
          standard.reload
          latest_version = standard.latest_version

          # Build stats hash for the card partial (similar to index method)
          stats = {
            standard: standard,
            latest_version: latest_version,
            clause_count: 0,
            checklist_count: 0,
            subclause_count: 0,
            compliance_percentage: 0,
            tool_compliance_data: [],
            company_count: nil,
            average_company_compliance: nil,
            is_processing: true  # Job is queued, so it's processing
          }

          html = render_to_string(partial: "standards/card", locals: { stats: stats }, formats: [ :html ])
          notification_html = render_to_string(partial: "shared/notification", locals: { message: flash[:notice], type: :success, animated: true }, formats: [ :html ])

          render json: {
            html: html,
            message: flash[:notice],
            type: "success",
            notification_html: notification_html,
            standard_id: standard.id
          }
        end
      end

    rescue ActiveRecord::RecordInvalid => e
      # Code uniqueness error: return both locales so frontend can show the right one
      code_taken = e.record.is_a?(Standard) && (
        e.record.errors.added?(:code, :taken) ||
        e.record.errors[:code]&.any? { |msg| msg.to_s.include?("taken") } ||
        e.record.errors.full_messages.first.to_s.include?("Code has already been taken")
      )
      if code_taken
        message_en = I18n.t("standard_upload_code_taken", locale: :en)
        message_ar = I18n.t("standard_upload_code_taken", locale: :ar)
        render json: { message: message_en, message_ar: message_ar }, status: :unprocessable_entity
        return
      end

      message = e.record.errors.full_messages.first.presence || e.message
      message = message.to_s.sub(/\AValidation failed:\s*/i, "")
      render json: { message: message }, status: :unprocessable_entity
    rescue => e
      Rails.logger.error "Upload error: #{e.message}"
      Rails.logger.error "Backtrace: #{e.backtrace.first(5)}"

      # If we created an ingestion job, mark it as failed
      if defined?(ingestion_job) && ingestion_job
        ingestion_job.fail!("Upload processing failed: #{e.message}")
      end

      message = "An error occurred while processing the upload."
      message = e.message if e.message.present? && e.message.length < 200
      render json: { message: message }, status: :internal_server_error
    end
  end

  def job_status
    standard = Standard.find_by(id: params[:id])

    unless standard
      render json: { error: "Standard not found" }, status: :not_found
      return
    end
    unless standard_accessible_to_user?(standard)
      render json: { error: "You don't have access to this standard." }, status: :forbidden
      return
    end

    # Find the most recent ingestion job for this standard
    ingestion_job = standard.ingestion_jobs.order(created_at: :desc).first

    unless ingestion_job
      render json: { error: "No ingestion job found" }, status: :not_found
      return
    end

    respond_to do |format|
      format.json do
        # If job is completed or failed, return the updated card HTML
        if ingestion_job.completed? || ingestion_job.failed?
          # Reload standard to get latest version
          standard.reload
          latest_version = standard.latest_version

          if latest_version
            clause_count = latest_version.clauses.count
            checklist_count = latest_version.clauses.joins(:checklist_items).count
            subclause_count = latest_version.clauses.where.not(parent_id: nil).count

            # Calculate compliance and get tool details
            compliance_data = calculate_compliance_with_details(standard, latest_version)

            # For platform admins, calculate company-wide statistics
            company_stats = if current_user&.platform_admin?
              calculate_company_wide_stats(standard, latest_version)
            else
              nil
            end

            stats = {
              standard: standard,
              latest_version: latest_version,
              clause_count: clause_count,
              checklist_count: checklist_count,
              subclause_count: subclause_count,
              compliance_percentage: compliance_data[:average_compliance],
              tool_compliance_data: compliance_data[:tool_data],
              company_count: company_stats&.[](:company_count),
              average_company_compliance: company_stats&.[](:average_compliance),
              is_processing: false  # Job is completed/failed, no longer processing
            }
          else
            stats = {
              standard: standard,
              latest_version: nil,
              clause_count: 0,
              checklist_count: 0,
              subclause_count: 0,
              compliance_percentage: 0,
              tool_compliance_data: [],
              company_count: nil,
              average_company_compliance: nil,
              is_processing: false
            }
          end

          html = render_to_string(partial: "standards/card", locals: { stats: stats }, formats: [ :html ])

          render json: {
            status: ingestion_job.status,
            completed: ingestion_job.completed?,
            failed: ingestion_job.failed?,
            html: html,
            message: ingestion_job.message
          }
        else
          # Job still processing, return status only
          render json: {
            status: ingestion_job.status,
            completed: false,
            failed: false,
            message: ingestion_job.message
          }
        end
      end
    end
  end

  def new_version
    @standard = Standard.find(params[:id])
  end

  def create_version
    @standard = Standard.find(params[:id])

    version_label = params[:version_label]
    pdf_file = params[:pdf_file]
    notes = params[:notes]

    unless pdf_file
      redirect_to standard_path(@standard), alert: "Please upload a PDF or XLSX file"
      return
    end

    allowed_types = %w[application/pdf application/vnd.openxmlformats-officedocument.spreadsheetml.sheet]
    unless allowed_types.include?(pdf_file.content_type)
      redirect_to standard_path(@standard), alert: "Only PDF and Excel (XLSX) files are allowed"
      return
    end

    begin
      uploaded_by_id = current_user.id

      # Standard documents (PDF/XLSX) are system-level documents, not company-specific
      # Super admins upload standard versions without a company association
      company_id = nil

      upload = Upload.create_from_uploaded_file(pdf_file, uploaded_by_id, company_id: company_id)

      # Create standard version first
      _standard_version = StandardVersion.create!(
        standard: @standard,
        version_label: version_label,
        source_pdf: upload,
        status: "draft",
        notes: notes
      )

      # Then create ingestion job
      ingestion_job = IngestionJob.create!(
        standard_id: @standard.id,
        input_pdf_id: upload.id,
        status: "queued",
        created_by: uploaded_by_id
      )

      ProcessIngestionJob.perform_async(ingestion_job.id)

      redirect_to standard_path(@standard), notice: "New version '#{version_label}' created successfully and is being processed"

    rescue => e
      Rails.logger.error "Create version error: #{e.message}"
      redirect_to standard_path(@standard), alert: "Failed to create version: #{e.message}"
    end
  end

  def publish_version
    @standard = Standard.find(params[:id])
    version = StandardVersion.find_by(id: params[:version_id], standard_id: @standard.id)

    unless version
      redirect_to edit_standard_path(@standard), alert: "Version not found"
      return
    end

    skip_assigning = params[:skip_assigning] == "true"
    company_ids = params[:company_ids] || []

    begin
      # Update version status to published
      version.update!(status: "published")

      # Assign version to selected companies if not skipping
      unless skip_assigning
        unless current_user&.can_assign_standards_to_companies?
          redirect_to edit_standard_path(@standard, version_id: version.id), alert: "You don't have permission to assign standards to companies."
          return
        end

        company_ids.each do |company_id|
          company = Company.find_by(id: company_id)
          next unless company

          # Find or create company_standard record
          company_standard = CompanyStandard.find_or_initialize_by(
            company_id: company.id,
            standard_id: @standard.id
          )

          # If it's a new assignment or version change, record history
          if company_standard.new_record?
            company_standard.assign_attributes(
              status: "active",
              active_version_id: version.id,
              assigned_by: current_user.id,
              assigned_at: Time.current
            )
            company_standard.save!
          elsif company_standard.active_version_id != version.id
            # Record version change in history
            company_standard.change_version(version.id, current_user.id, "Published version #{version.version_label}")
          end
        end
      end

      flash[:notice] = "Version #{version.version_label} has been published successfully!"
      redirect_to standard_path(@standard)
    rescue => e
      Rails.logger.error "Publish version error: #{e.message}"
      redirect_to edit_standard_path(@standard, version_id: version.id), alert: "Failed to publish version: #{e.message}"
    end
  end

  def destroy
    unless current_user&.platform_admin?
      respond_to do |format|
        format.json {
          render json: {
            error: "You don't have permission to delete standards.",
            success: false
          }, status: :forbidden
        }
      end
      return
    end

    @standard = Standard.find(params[:id])
    standard_name = @standard.code

    respond_to do |format|
      begin
        # Log audit action before deletion
        AuditLogService.log_action(
          actor_user: current_user,
          company: current_company,
          action: "DELETE_STANDARD",
          entity_type: "standard",
          entity_id: @standard.id,
          payload: {
            standard_id: @standard.id,
            standard_code: @standard.code,
            standard_name: standard_name
          }
        )

        # This will cascade delete all associated records:
        # - StandardVersions (through dependent: :destroy)
        # - StandardTranslations (through dependent: :destroy)
        # - And all nested associations (clauses, checkpoints, etc.)
        @standard.destroy!

        format.json {
          render json: {
            message: "Standard '#{standard_name}' and all its associated data have been successfully deleted.",
            success: true
          }, status: :ok
        }
      rescue ActiveRecord::InvalidForeignKey, ActiveRecord::StatementInvalid => e
        if (e.cause && e.cause.class.name == "PG::ForeignKeyViolation") || e.message.to_s.include?("foreign key")
          Rails.logger.error "Failed to delete standard #{@standard.id}: #{e.message}"
          format.json {
            render json: {
              error: "This standard cannot be deleted because it is still linked to other records (e.g. CAPAs). Unlink or remove those first, then try again.",
              success: false
            }, status: :unprocessable_entity
          }
        else
          raise e
        end
      rescue => e
        Rails.logger.error "Failed to delete standard #{@standard.id}: #{e.message}"

        format.json {
          render json: {
            error: "Failed to delete standard: #{e.message}",
            success: false
          }, status: :unprocessable_entity
        }
      end
    end
  end


  def mark_clause_reviewed
    clause = Clause.find(params[:clause_id])
    language_code = params[:language_code] || I18n.locale.to_s

    translation = clause.clause_translations.find_by(language_code: language_code)

    if translation
      # When marking as reviewed, update source_updated_at to current time
      # This ensures that future updates to other languages won't mark this as needing review
      # unless they are actually newer than when this was reviewed
      translation.update(
        needs_review: false,
        source_updated_at: Time.current
      )
      respond_to do |format|
        format.json {
          render json: {
            message: "Clause marked as reviewed",
            clause_id: clause.id,
            language_code: language_code
          }, status: :ok
        }
      end
    else
      respond_to do |format|
        format.json { render json: { error: "Translation not found" }, status: :not_found }
      end
    end
  rescue => e
    respond_to do |format|
      format.json { render json: { error: e.message }, status: :unprocessable_entity }
    end
  end

  def mark_checkpoint_reviewed
    checklist_item = ChecklistItem.find(params[:checkpoint_id])
    language_code = params[:language_code] || I18n.locale.to_s

    translation = checklist_item.checklist_item_translations.find_by(language_code: language_code)

    if translation
      # When marking as reviewed, update source_updated_at to current time
      # This ensures that future updates to other languages won't mark this as needing review
      # unless they are actually newer than when this was reviewed
      translation.update(
        needs_review: false,
        source_updated_at: Time.current
      )
      respond_to do |format|
        format.json {
          render json: {
            message: "Checkpoint marked as reviewed",
            checkpoint_id: checklist_item.id,
            language_code: language_code
          }, status: :ok
        }
      end
    else
      respond_to do |format|
        format.json { render json: { error: "Translation not found" }, status: :not_found }
      end
    end
  rescue => e
    respond_to do |format|
      format.json { render json: { error: e.message }, status: :unprocessable_entity }
    end
  end

  def update_clause_points
    clause = Clause.find(params[:clause_id])
    base_points = params[:base_points].to_f

    unless clause.root?
      respond_to do |format|
        format.json { render json: { error: "Sub-clause weights must be edited via their parent's distribute action" }, status: :unprocessable_entity }
      end
      return
    end

    if base_points <= 0
      respond_to do |format|
        format.json { render json: { error: "Points must be greater than 0" }, status: :unprocessable_entity }
      end
      return
    end

    begin
      clause.update!(base_points: base_points)

      standard = clause.standard_version&.standard
      ClauseScorePropagator.invalidate_cache_for_tool_clause_changes(standard, [ clause ]) if standard

      children_sum = clause.children.sum(:base_points).to_f

      respond_to do |format|
        format.json {
          render json: {
            message: "Points updated successfully",
            clause_id: clause.id,
            base_points: clause.base_points,
            children_sum: children_sum,
            children_match: clause.children.empty? || (children_sum - clause.base_points.to_f).abs < 0.01
          }, status: :ok
        }
      end
    rescue => e
      respond_to do |format|
        format.json { render json: { error: e.message }, status: :unprocessable_entity }
      end
    end
  end

  TOLERANCE = 0.01

  def distribute_weights
    parent = Clause.find(params[:parent_id])
    weights = params[:weights] || {}
    weights = weights.to_unsafe_h if weights.respond_to?(:to_unsafe_h)

    children = parent.children.to_a
    if children.empty?
      return render json: { error: "Clause has no sub-clauses" }, status: :unprocessable_entity
    end

    parsed = {}
    weights.each do |child_id, value|
      points = value.to_f
      if points < 0
        return render json: { error: "Weights must be non-negative" }, status: :unprocessable_entity
      end
      parsed[child_id.to_s] = points
    end

    expected_ids = children.map { |c| c.id.to_s }.sort
    given_ids = parsed.keys.sort
    if expected_ids != given_ids
      return render json: { error: "Weights must include exactly all sub-clauses" }, status: :unprocessable_entity
    end

    parent_points = parent.base_points.to_f
    if parent_points <= 0
      return render json: { error: "Parent clause has no base points set" }, status: :unprocessable_entity
    end

    sum = parsed.values.sum
    if (sum - parent_points).abs > TOLERANCE
      return render json: {
        error: "Sub-clause weights must sum to #{parent_points} (got #{sum.round(2)})",
        parent_points: parent_points,
        sum: sum.round(2)
      }, status: :unprocessable_entity
    end

    begin
      ActiveRecord::Base.transaction do
        children.each do |child|
          new_points = parsed[child.id.to_s]
          child.update!(base_points: new_points, allocated_points: new_points)
        end
      end

      standard = parent.standard_version&.standard
      ClauseScorePropagator.invalidate_cache_for_tool_clause_changes(standard, [ parent ]) if standard

      render json: {
        message: "Sub-clause weights saved",
        parent_id: parent.id,
        parent_points: parent_points,
        sum: sum.round(2),
        weights: parsed.transform_values { |v| v.round(2) }
      }, status: :ok
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
    rescue => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end

  def rollup_weights
    parent = Clause.find(params[:parent_id])
    weights = params[:weights] || {}
    weights = weights.to_unsafe_h if weights.respond_to?(:to_unsafe_h)

    children = parent.children.to_a
    if children.empty?
      return render json: { error: "Clause has no sub-clauses" }, status: :unprocessable_entity
    end

    parsed = {}
    weights.each do |child_id, value|
      points = value.to_f
      if points < 0
        return render json: { error: "Weights must be non-negative" }, status: :unprocessable_entity
      end
      parsed[child_id.to_s] = points
    end

    expected_ids = children.map { |c| c.id.to_s }.sort
    given_ids = parsed.keys.sort
    if expected_ids != given_ids
      return render json: { error: "Weights must include exactly all sub-clauses" }, status: :unprocessable_entity
    end

    sum = parsed.values.sum
    if sum <= 0
      return render json: { error: "Sum of sub-clause weights must be greater than 0" }, status: :unprocessable_entity
    end

    begin
      ActiveRecord::Base.transaction do
        children.each do |child|
          new_points = parsed[child.id.to_s]
          child.update!(base_points: new_points, allocated_points: new_points)
        end
        parent.update!(base_points: sum, allocated_points: sum)
      end

      standard = parent.standard_version&.standard
      ClauseScorePropagator.invalidate_cache_for_tool_clause_changes(standard, [ parent ]) if standard

      grandparent_match = if parent.parent_id.present?
        siblings_sum = Clause.where(parent_id: parent.parent_id).sum(:base_points).to_f
        grandparent_points = parent.parent.base_points.to_f
        grandparent_points > 0 && (siblings_sum - grandparent_points).abs < TOLERANCE
      else
        true
      end

      render json: {
        message: "Parent set to #{sum.round(2)} pts and sub-clauses saved",
        parent_id: parent.id,
        parent_points: sum.round(2),
        sum: sum.round(2),
        grandparent_match: grandparent_match
      }, status: :ok
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
    rescue => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end

  private

  # Require super admin authorization
  def standard_accessible_to_user?(standard)
    return false unless standard && current_user
    return true if current_user.super_admin? || current_user.delegated_admin?
    return false unless current_user.company_user&.company_id
    CompanyStandard.exists?(standard_id: standard.id, company_id: current_user.company_user.company_id, status: "active")
  end

  def require_platform_admin
    return if current_user&.platform_admin?

    error_message = "You don't have permission to perform this action."
    notification_html = render_to_string(partial: "shared/notification", locals: { message: error_message, type: :error, animated: true }, formats: [ :html ])
    respond_to do |format|
      format.json do
        render json: {
          message: error_message,
          type: "error",
          notification_html: notification_html
        }, status: :forbidden
      end
      format.html do
        redirect_to root_path, alert: error_message, status: :see_other
      end
    end
    nil
  end

  def is_descendant?(potential_descendant, ancestor)
    current = potential_descendant
    while current.present?
      return true if current.id == ancestor.id
      current = current.parent
    end
    false
  end

  def recalculate_all_sibling_codes(parent_clause, updated_descendants)
    # Get all children of this parent, ordered by sort_order
    children = parent_clause.children.ordered

    children.each_with_index do |child, index|
      # Calculate the new code based on parent's code and position (1-indexed)
      new_code = "#{parent_clause.code}.#{index + 1}"

      # Update the clause code
      child.update_columns(code: new_code)
      updated_descendants[child.id] = new_code

      # Recursively update all descendants of this child
      update_all_descendant_codes(child, updated_descendants) if child.children.any?
    end
  end

  def update_all_descendant_codes(parent_clause, updated_descendants)
    # Get all children ordered by sort_order
    children = parent_clause.children.ordered

    children.each_with_index do |child, index|
      # Calculate new code based on parent's code
      new_code = "#{parent_clause.code}.#{index + 1}"
      child.update_columns(code: new_code)
      updated_descendants[child.id] = new_code

      # Recursively update this child's descendants
      update_all_descendant_codes(child, updated_descendants) if child.children.any?
    end
  end


  # Auto-translate clause to all other available languages
  def translate_clause_to_other_languages(clause, source_locale, source_title)
    available_locales = I18n.available_locales.map(&:to_s)
    target_locales = available_locales - [ source_locale ]

    target_locales.each do |target_locale|
      begin
        # Use Ollama to translate the title
        translated_title = translate_text_with_ollama(source_title, source_locale, target_locale)

        if translated_title.present? && translated_title.strip != "[Translation needed]"
          translation = clause.clause_translations.find_or_initialize_by(language_code: target_locale)
          translation.title = translated_title
          translation.summary = "" if translation.summary.blank?
          translation.body = "" if translation.body.blank?
          translation.save!
          # Auto-translated content should be flagged for human review.
          # update_column bypasses the after_save callback that would otherwise
          # clear needs_review whenever the translation content changes.
          translation.update_column(:needs_review, true)
          Rails.logger.info "Auto-translated clause #{clause.id} to #{target_locale}"
        else
          Rails.logger.warn "Translation failed for clause #{clause.id} to #{target_locale}, creating/updating placeholder"
          # Create or update placeholder translation that needs review
          translation = clause.clause_translations.find_or_initialize_by(language_code: target_locale)
          translation.title = "[Translation needed]" if translation.title.blank?
          translation.summary = "" if translation.summary.blank?
          translation.body = "" if translation.body.blank?
          translation.needs_review = true
          translation.save!
        end
      rescue => e
        Rails.logger.error "Error translating clause #{clause.id} to #{target_locale}: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
        # Create or update placeholder translation on error
        begin
          translation = clause.clause_translations.find_or_initialize_by(language_code: target_locale)
          translation.title = "[Translation needed]" if translation.title.blank?
          translation.summary = "" if translation.summary.blank?
          translation.body = "" if translation.body.blank?
          translation.needs_review = true
          translation.save!
        rescue => create_error
          Rails.logger.error "Failed to create placeholder translation: #{create_error.message}"
        end
      end
    end
  end

  # Auto-translate checkpoint to all other available languages
  def translate_checkpoint_to_other_languages(checkpoint, source_locale, source_text)
    available_locales = I18n.available_locales.map(&:to_s)
    target_locales = available_locales - [ source_locale ]

    target_locales.each do |target_locale|
      begin
        # Use Ollama to translate the text
        translated_text = translate_text_with_ollama(source_text, source_locale, target_locale)

        if translated_text.present? && translated_text.strip != "[Translation needed]"
          translation = checkpoint.checklist_item_translations.find_or_initialize_by(language_code: target_locale)
          translation.text = translated_text
          translation.save!
          # Flag auto-translated content for review; update_column bypasses the
          # after_save callback that clears needs_review on content change.
          translation.update_column(:needs_review, true)
          Rails.logger.info "Auto-translated checkpoint #{checkpoint.id} to #{target_locale}"
        else
          Rails.logger.warn "Translation failed for checkpoint #{checkpoint.id} to #{target_locale}, creating/updating placeholder"
          # Create or update placeholder translation that needs review
          translation = checkpoint.checklist_item_translations.find_or_initialize_by(language_code: target_locale)
          translation.text = "[Translation needed]" if translation.text.blank?
          translation.needs_review = true
          translation.save!
        end
      rescue => e
        Rails.logger.error "Error translating checkpoint #{checkpoint.id} to #{target_locale}: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
        # Create or update placeholder translation on error
        begin
          translation = checkpoint.checklist_item_translations.find_or_initialize_by(language_code: target_locale)
          translation.text = "[Translation needed]" if translation.text.blank?
          translation.needs_review = true
          translation.save!
        rescue => create_error
          Rails.logger.error "Failed to create placeholder translation: #{create_error.message}"
        end
      end
    end
  end

  # Simple text translation using Ollama
  def translate_text_with_ollama(text, source_language, target_language)
    return nil if text.blank?

    # Language name mapping
    language_names = {
      "en" => "English",
      "ar" => "Arabic"
    }

    source_name = language_names[source_language] || source_language
    target_name = language_names[target_language] || target_language

    prompt = <<~PROMPT
      Translate the following text from #{source_name} to #{target_name}.
      Preserve the technical meaning exactly and maintain proper terminology.
      Return ONLY the translated text, nothing else.

      Text to translate:
      #{text}
    PROMPT

    begin
      ollama_url = ENV.fetch("OLLAMA_URL", "http://localhost:11434")
      model = ENV.fetch("TRANSLATION_OLLAMA_MODEL", "qwen2.5:14b-instruct")

      client = OllamaClient.new(model: model, base_url: ollama_url)
      translated = client.generate(prompt, max_tokens: 2000)

      # Clean up the response (remove any extra text, JSON markers, etc.)
      translated = translated.strip
      translated = translated.gsub(/^```json\s*/, "").gsub(/\s*```$/, "")
      translated = translated.gsub(/^```\s*/, "").gsub(/\s*```$/, "")
      translated = translated.gsub(/^["']|["']$/, "") # Remove surrounding quotes

      translated.present? ? translated : nil
    rescue => e
      Rails.logger.error "Ollama translation error: #{e.message}"
      nil
    end
  end
end
