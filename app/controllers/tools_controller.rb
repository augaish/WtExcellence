class ToolsController < Dashboard::BaseController
  # Tools section is only for super admins and delegated admins with manage_tools permission
  # Assignment-related actions are also allowed for company admins (e.g. when assigning from standards clause hierarchy)
  before_action :require_tools_access, except: [
    :get_assignments,
    :assign_multiple_users_to_subcheckpoint
  ]
  before_action :require_tools_or_company_admin_for_assignments, only: [
    :get_assignments,
    :assign_multiple_users_to_subcheckpoint
  ]

  def index
    @tools = Tool.includes(clauses: { standard_version: :standard }).all
    @standards = Standard.all.includes(:standard_translations).order(:code)

    if params[:search].present?
      search_term = "%#{params[:search]}%"
      @tools = @tools.where(
        "tools.name ILIKE ? OR tools.description ILIKE ?",
        search_term, search_term
      )
    end

    if params[:standard_id].present? && params[:standard_id] != "all"
      @tools = @tools.joins(clauses: { standard_version: :standard })
                     .where(standards: { id: params[:standard_id] })
                     .distinct
    end

    # Sorting
    case params[:sort]
    when "last_edited"
      @tools = @tools.order(updated_at: :desc)
    when "creation_date"
      @tools = @tools.order(created_at: :desc)
    else
      # Default: last edited
      @tools = @tools.order(updated_at: :desc)
    end
  end

    def new
        return if prevent_viewer_action
        @tool = Tool.new
        load_company_users
    end

    def create
      return if prevent_viewer_action
      # Process multiple choice options before building tool
      process_multiple_choice_options_in_params

      @tool = Tool.new(tool_params)

      # Process business rules
      process_business_rules

      # Process multiple choice options on the built tool
      process_multiple_choice_options_on_tool

      if @tool.save
        synchronize_tool_translations(@tool)
        # Log audit action for tool creation
        AuditLogService.log_action(
          actor_user: current_user,
          company: current_company,
          action: "CREATE_TOOL",
          entity_type: "tool",
          entity_id: @tool.id,
          payload: {
            tool_id: @tool.id,
            tool_name: @tool.name,
            tool_description: @tool.description,
            clause_count: @tool.clauses.count,
            checkpoint_count: @tool.checkpoints.count
          }
        )
        redirect_to tools_path, notice: "Tool created successfully"
      else
        # Rebuild nested structure from params to preserve form data
        rebuild_nested_attributes_from_params
        render :new, status: :unprocessable_entity
      end
    end

    def show
      @tool = Tool.includes(
        :tool_translations,
        checkpoints: [ :tool_checkpoint_translations, { subcheckpoints: :tool_subcheckpoint_translations } ],
        tool_clauses: [],
        clauses: { standard_version: { standard: :standard_translations } }
      ).find(params[:id])
      @standards = Standard.all.includes(:standard_translations).order(:code)
      @current_locale = I18n.locale.to_s
      load_company_users
    end

    def link_standard
      return if prevent_viewer_action
      @tool = Tool.find(params[:id])
      standard_id = params[:standard_id]
      clauses_data = params[:clauses] || []
      clauses_data = clauses_data.to_unsafe_h if clauses_data.respond_to?(:to_unsafe_h)

      if standard_id.blank?
        redirect_to tool_path(@tool), alert: "Please select a standard"
        return
      end

      if clauses_data.empty?
        redirect_to tool_path(@tool), alert: "Please add at least one clause"
        return
      end

      begin
        total_linked = 0
        linked_clauses_summary = []
        errors = []

        ActiveRecord::Base.transaction do
          clauses_data.each do |key, clause_data|
            clause_id = clause_data["clause_id"] || clause_data[:clause_id]

            next if clause_id.blank?

            # Find the top-level clause
            top_level_clause = Clause.find_by(id: clause_id)
            unless top_level_clause
              errors << "Clause #{clause_id} not found"
              next
            end

            # Verify it's a root clause
            unless top_level_clause.root?
              errors << "Clause #{top_level_clause.code} is not a top-level clause"
              next
            end

            # Check if already linked to another tool
            terminal_clauses = get_all_terminal_clauses(top_level_clause)
            already_linked = terminal_clauses.select do |tc|
              existing_tool_clause = ToolClause.find_by(clause_id: tc.id)
              existing_tool_clause && existing_tool_clause.tool_id != @tool.id
            end

            if already_linked.any?
              errors << "Clause #{top_level_clause.code} is already linked to another tool"
              next
            end

            # Link all terminal clauses to the tool. Weights are managed via the
            # clause-tree edit page, not here.
            linked_count = 0
            terminal_clauses.each do |terminal_clause|
              tool_clause = @tool.tool_clauses.find_or_create_by!(clause_id: terminal_clause.id)
              linked_count += 1 if tool_clause.persisted?
            end

            total_linked += linked_count
            linked_clauses_summary << "#{top_level_clause.code} (#{linked_count} terminal clauses)"
          end
        end

        if total_linked > 0
          # Log audit action for linking standard
          standard = Standard.find(standard_id)
          AuditLogService.log_action(
            actor_user: current_user,
            company: current_company,
            action: "LINK_STANDARD_TO_TOOL",
            entity_type: "tool",
            entity_id: @tool.id,
            payload: {
              tool_id: @tool.id,
              tool_name: @tool.name,
              standard_id: standard_id,
              standard_name: standard.display_name("en") || standard.code,
              standard_code: standard.code,
              clauses_linked: total_linked,
              clauses_summary: linked_clauses_summary
            }
          )
          # Invalidate company standard score caches so compliance is recalculated for assigned companies
          root_clauses_linked = Clause.where(id: clauses_data.map { |_k, d| d["clause_id"] || d[:clause_id] }.compact.uniq)
          ClauseScorePropagator.invalidate_cache_for_tool_clause_changes(standard, root_clauses_linked)
          message = "Successfully linked: #{linked_clauses_summary.join(', ')}"
          message += ". Errors: #{errors.join('; ')}" if errors.any?
          redirect_to tool_path(@tool), notice: message
        elsif errors.any?
          redirect_to tool_path(@tool), alert: "Failed to link clauses: #{errors.join('; ')}"
        else
          redirect_to tool_path(@tool), alert: "No clauses were linked"
        end
      rescue => e
        Rails.logger.error "Error linking standard: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        redirect_to tool_path(@tool), alert: "Failed to link clauses: #{e.message}"
      end
    end

    def switch_clause_tool
      return if prevent_viewer_action

      clause_id = params[:clause_id]
      tool_id = params[:tool_id]

      unless clause_id.present? && tool_id.present?
        render json: { success: false, error: "Missing required parameters: clause_id and tool_id are required" }, status: :unprocessable_entity
        return
      end

      begin
        # Find the clause (must be root level)
        clause = Clause.find_by(id: clause_id)
        unless clause
          render json: { success: false, error: "Clause not found" }, status: :not_found
          return
        end

        unless clause.root?
          render json: { success: false, error: "Only root-level clauses can be linked to tools" }, status: :unprocessable_entity
          return
        end

        # Find the tool
        tool = Tool.find_by(id: tool_id)
        unless tool
          render json: { success: false, error: "Tool not found" }, status: :not_found
          return
        end

        # Get all terminal clauses
        terminal_clauses = get_all_terminal_clauses(clause)
        terminal_clause_ids = terminal_clauses.map(&:id)

        # Get old tool if exists (check first terminal clause)
        old_tool = nil
        if terminal_clause_ids.any?
          old_tool_clause = ToolClause.find_by(clause_id: terminal_clause_ids.first)
          old_tool = old_tool_clause&.tool
        end

        # If switching to a different tool, unlink from old tool first
        if old_tool && old_tool.id != tool.id
          # Verify all terminal clauses are linked to the old tool
          old_tool_clauses = ToolClause.where(clause_id: terminal_clause_ids, tool_id: old_tool.id)
          if old_tool_clauses.count != terminal_clause_ids.count
            render json: { success: false, error: "Clause #{clause.code} is partially linked to different tools. Cannot switch." }, status: :unprocessable_entity
            return
          end
        end

        total_linked = 0
        ActiveRecord::Base.transaction do
          # If switching tools, unlink from old tool first
          if old_tool && old_tool.id != tool.id
            ToolClause.where(clause_id: terminal_clause_ids, tool_id: old_tool.id).destroy_all
          end

          # Link all terminal clauses to the new tool. Weights are managed via
          # the clause-tree edit page, not here.
          terminal_clauses.each do |terminal_clause|
            tool_clause = tool.tool_clauses.find_or_create_by!(clause_id: terminal_clause.id)
            total_linked += 1 if tool_clause.persisted?
          end
        end

        # Log audit action
        AuditLogService.log_action(
          actor_user: current_user,
          company: current_company,
          action: old_tool ? "SWITCH_CLAUSE_TOOL" : "LINK_CLAUSE_TOOL",
          entity_type: "clause",
          entity_id: clause.id,
          payload: {
            clause_id: clause.id,
            clause_code: clause.code,
            old_tool_id: old_tool&.id,
            old_tool_name: old_tool&.name,
            new_tool_id: tool.id,
            new_tool_name: tool.name,
            terminal_clauses_linked: total_linked
          }
        )

        # Invalidate company standard score caches for assigned companies
        standard = clause.standard_version&.standard
        ClauseScorePropagator.invalidate_cache_for_tool_clause_changes(standard, [clause]) if standard

        render json: {
          success: true,
          message: old_tool ? "Tool switched successfully" : "Tool linked successfully",
          clause_id: clause.id,
          tool_id: tool.id,
          tool_name: tool.name
        }
      rescue => e
        Rails.logger.error "Error switching clause tool: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        render json: { success: false, error: "Failed to switch tool: #{e.message}" }, status: :unprocessable_entity
      end
    end

    def unlink_clause_tool
      return if prevent_viewer_action

      clause_id = params[:clause_id]
      tool_id = params[:tool_id]

      unless clause_id.present? && tool_id.present?
        render json: { success: false, error: "Missing required parameters: clause_id and tool_id are required" }, status: :unprocessable_entity
        return
      end

      begin
        # Find the clause (must be root level)
        clause = Clause.find_by(id: clause_id)
        unless clause
          render json: { success: false, error: "Clause not found" }, status: :not_found
          return
        end

        unless clause.root?
          render json: { success: false, error: "Only root-level clauses can be unlinked from tools" }, status: :unprocessable_entity
          return
        end

        # Find the tool
        tool = Tool.find_by(id: tool_id)
        unless tool
          render json: { success: false, error: "Tool not found" }, status: :not_found
          return
        end

        # Get all terminal clauses under this root clause
        terminal_clauses = get_all_terminal_clauses(clause)
        terminal_clause_ids = terminal_clauses.map(&:id)

        if terminal_clause_ids.empty?
          render json: { success: false, error: "No terminal clauses found for #{clause.code}" }, status: :unprocessable_entity
          return
        end

        # Verify all terminal clauses are linked to this tool
        tool_clauses = ToolClause.where(clause_id: terminal_clause_ids, tool_id: tool.id)
        if tool_clauses.count != terminal_clause_ids.count
          render json: { success: false, error: "Not all terminal clauses are linked to this tool" }, status: :unprocessable_entity
          return
        end

        total_unlinked = 0
        ActiveRecord::Base.transaction do
          # Unlink all terminal clauses. Weights stay on the clauses — they belong
          # to the standard, not to the tool.
          total_unlinked = tool_clauses.destroy_all.count
        end

        # Log audit action
        AuditLogService.log_action(
          actor_user: current_user,
          company: current_company,
          action: "UNLINK_CLAUSE_TOOL",
          entity_type: "clause",
          entity_id: clause.id,
          payload: {
            clause_id: clause.id,
            clause_code: clause.code,
            tool_id: tool.id,
            tool_name: tool.name,
            terminal_clauses_unlinked: total_unlinked
          }
        )

        # Invalidate company standard score caches for assigned companies
        standard = clause.standard_version&.standard
        ClauseScorePropagator.invalidate_cache_for_tool_clause_changes(standard, [clause]) if standard

        render json: {
          success: true,
          message: "Tool unlinked successfully",
          clause_id: clause.id,
          tool_id: tool.id,
          terminal_clauses_unlinked: total_unlinked
        }
      rescue => e
        Rails.logger.error "Error unlinking clause tool: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        render json: { success: false, error: "Failed to unlink tool: #{e.message}" }, status: :unprocessable_entity
      end
    end

    def unlink_standard
      return if prevent_viewer_action
      @tool = Tool.find(params[:id])
      standard_id = params[:standard_id]
      top_level_clause_ids = params[:top_level_clause_ids] || []

      if standard_id.blank?
        redirect_to tool_path(@tool), alert: "Standard ID is required"
        return
      end

      if top_level_clause_ids.empty?
        redirect_to tool_path(@tool), alert: "Please select at least one clause to unlink"
        return
      end

      total_unlinked = 0
      unlinked_clauses = []
      errors = []

      ActiveRecord::Base.transaction do
        top_level_clause_ids.each do |clause_id|
          next if clause_id.blank?

          # Find the top-level clause
          top_level_clause = Clause.find_by(id: clause_id)
          unless top_level_clause
            errors << "Clause #{clause_id} not found"
            next
          end

          # Get all terminal clauses under this top-level clause
          terminal_clauses = get_all_terminal_clauses(top_level_clause)
          terminal_clause_ids = terminal_clauses.map(&:id)

          if terminal_clause_ids.empty?
            errors << "No terminal clauses found for #{top_level_clause.code}"
            next
          end

          # Unlink all terminal clauses
          unlinked_count = @tool.tool_clauses.where(clause_id: terminal_clause_ids).destroy_all.count

          if unlinked_count > 0
            total_unlinked += unlinked_count
            unlinked_clauses << "#{top_level_clause.code} (#{unlinked_count} terminal clauses)"
          end
        end
      end

      # Check if all clauses for this standard have been unlinked
      standard = Standard.find(standard_id)
      remaining_clauses = Clause.joins(:standard_version)
                                .where(standard_versions: { standard_id: standard.id })
                                .joins(:tool_clause)
                                .where(tool_clauses: { tool_id: @tool.id })
                                .count

      if total_unlinked > 0
        # Log audit action for unlinking standard
        AuditLogService.log_action(
          actor_user: current_user,
          company: current_company,
          action: "UNLINK_STANDARD_FROM_TOOL",
          entity_type: "tool",
          entity_id: @tool.id,
          payload: {
            tool_id: @tool.id,
            tool_name: @tool.name,
            standard_id: standard_id,
            standard_name: standard.display_name("en") || standard.code,
            standard_code: standard.code,
            clauses_unlinked: total_unlinked,
            clauses_summary: unlinked_clauses,
            standard_removed: remaining_clauses == 0
          }
        )
        message = "Successfully unlinked: #{unlinked_clauses.join(', ')}"
        message += ". Standard removed from tool" if remaining_clauses == 0
        message += ". Errors: #{errors.join('; ')}" if errors.any?
        redirect_to tool_path(@tool), notice: message
      elsif errors.any?
        redirect_to tool_path(@tool), alert: "Failed to unlink clauses: #{errors.join('; ')}"
      else
        redirect_to tool_path(@tool), alert: "No clauses were unlinked"
      end
    rescue => e
      Rails.logger.error "Error unlinking clauses: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      redirect_to tool_path(@tool), alert: "Failed to unlink clauses: #{e.message}"
    end

    def edit
      return if prevent_viewer_action
      @tool = Tool.includes(checkpoints: :subcheckpoints).find(params[:id])
      @standards = Standard.all
      load_company_users
    end

    def update
      return if prevent_viewer_action
      @tool = Tool.find(params[:id])
      old_clause_ids = @tool.clause_ids
      tool_param = params[:tool] || ActionController::Parameters.new

      # Handle clause associations
      if tool_param.key?(:clause_ids)
        clause_ids = tool_param[:clause_ids].reject(&:blank?)
        @tool.clause_ids = clause_ids
      end

      # Process multiple choice options before updating
      process_multiple_choice_options_in_params

      # Process business rules (sets @tool.business_rules directly)
      process_business_rules

      # Prepare update params - include processed business_rules (safe when :tool is absent, e.g. "Save Rules" only)
      begin
        update_params = tool_params.to_h
      rescue ActionController::ParameterMissing
        update_params = {}
        # "Save Rules" with no tool params (e.g. user deleted all rules): persist empty business rules
        if params[:commit].present? && current_user&.can_manage_tools?
          @tool.business_rules = { "rules" => [] }
        end
      end
      if @tool.business_rules.present? || (tool_param[:business_rules].present? && current_user&.can_manage_tools?)
        update_params[:business_rules] = @tool.business_rules || {}
      end

      if @tool.update(update_params)
        # Process multiple choice options on the updated tool
        process_multiple_choice_options_on_tool
        synchronize_tool_translations(@tool)

        # Invalidate company standard score caches when clauses, business rules, or attributes change
        # so compliance is recalculated instead of showing stale data (e.g. new business rule violation).
        clause_ids_changed = (old_clause_ids.sort != @tool.clause_ids.sort)
        business_rules_changed = @tool.saved_change_to_business_rules?
        # Attributes = checkpoints/subcheckpoints; adding/removing them changes score and total_count
        attributes_changed = params.dig(:tool, :checkpoints_attributes).present?
        if clause_ids_changed || business_rules_changed || attributes_changed
          invalidate_company_score_cache_for_tool_changes(
            affected_clause_ids: (old_clause_ids + @tool.clause_ids).uniq,
            business_rules_only: business_rules_changed && !clause_ids_changed
          )
        end

        # When subcheckpoints change, reset approved/under_review assessments to needs_changes
        # so they must be re-evaluated with the new scoring attributes
        if attributes_changed
          Assessment.joins(:tool_clause)
            .where(tool_clauses: { tool_id: @tool.id })
            .where(status: %w[approved under_review])
            .update_all(status: "needs_changes")
        end

        # Track changes for audit log
        changes_to_track = {}
        changes_to_track["name"] = [ @tool.name_before_last_save, @tool.name ] if @tool.saved_change_to_name?
        changes_to_track["description"] = [ @tool.description_before_last_save, @tool.description ] if @tool.saved_change_to_description?
        changes_to_track["business_rules"] = true if @tool.saved_change_to_business_rules?

        # Log audit action for tool update
        AuditLogService.log_action(
          actor_user: current_user,
          company: current_company,
          action: "UPDATE_TOOL",
          entity_type: "tool",
          entity_id: @tool.id,
          payload: {
            tool_id: @tool.id,
            tool_name: @tool.name,
            changes: changes_to_track
          }
        )
        redirect_to tool_path(@tool), notice: "Business rules updated successfully"
      else
        @standards = Standard.all
        load_company_users
        redirect_to tool_path(@tool), alert: "Failed to update: #{@tool.errors.full_messages.join(', ')}"
      end
    end

    def bulk_destroy
      return if prevent_viewer_action

      tool_ids = Array(params[:tool_ids]).reject(&:blank?)

      if tool_ids.empty?
        render json: { success: false, error: I18n.t("bulk_delete_tools_no_selection") }, status: :unprocessable_entity
        return
      end

      tools = Tool.where(id: tool_ids)
      deleted_ids = []
      errors = []
      affected_clause_ids_total = []

      tools.each do |tool|
        tool_name = tool.name
        tool_id = tool.id
        affected_clause_ids = tool.clause_ids

        if affected_clause_ids.any?
          invalidate_company_score_cache_for_tool_changes(affected_clause_ids: affected_clause_ids)
          affected_clause_ids_total.concat(affected_clause_ids)
        end

        if tool.destroy
          deleted_ids << tool_id
          AuditLogService.log_action(
            actor_user: current_user,
            company: current_company,
            action: "DELETE_TOOL",
            entity_type: "tool",
            entity_id: tool_id,
            payload: {
              tool_id: tool_id,
              tool_name: tool_name,
              bulk: true
            }
          )
        else
          errors << "#{tool_name}: #{tool.errors.full_messages.join(', ')}"
        end
      end

      deleted_count = deleted_ids.size

      if deleted_count > 0 && errors.empty?
        render json: {
          success: true,
          message: I18n.t("bulk_delete_tools_success", count: deleted_count),
          deleted_count: deleted_count,
          deleted_ids: deleted_ids
        }
      elsif deleted_count > 0
        render json: {
          success: true,
          message: I18n.t("bulk_delete_tools_partial", count: deleted_count, errors: errors.join(", ")),
          deleted_count: deleted_count,
          deleted_ids: deleted_ids,
          errors: errors
        }
      else
        render json: {
          success: false,
          error: I18n.t("bulk_delete_tools_error", errors: errors.join(", "))
        }, status: :unprocessable_entity
      end
    end

    def destroy
      return if prevent_viewer_action
      @tool = Tool.find(params[:id])
      tool_name = @tool.name

      # Invalidate score caches BEFORE destroying (tool_clauses still exist)
      affected_clause_ids = @tool.clause_ids
      if affected_clause_ids.any?
        invalidate_company_score_cache_for_tool_changes(affected_clause_ids: affected_clause_ids)
      end

      if @tool.destroy
        # Log audit action for tool deletion
        AuditLogService.log_action(
          actor_user: current_user,
          company: current_company,
          action: "DELETE_TOOL",
          entity_type: "tool",
          entity_id: @tool.id,
          payload: {
            tool_id: @tool.id,
            tool_name: tool_name
          }
        )
        redirect_to tools_path, notice: "Tool '#{tool_name}' deleted successfully"
      else
        redirect_to tools_path, alert: "Failed to delete tool: #{@tool.errors.full_messages.join(', ')}"
      end
    rescue ActiveRecord::RecordNotFound
      redirect_to tools_path, alert: "Tool not found"
    end


    def assign_multiple_users_to_subcheckpoint
      return if prevent_viewer_action
      # Access already restricted by require_tools_access (super_admin or delegated_admin with manage_tools)

      tool_clause_id = params[:tool_clause_id]
      checklist_item_id = params[:checklist_item_id]
      contributor_ids = Array(params[:contributor_ids]).reject(&:blank?)
      users_to_remove = params[:users_to_remove]&.split(",")&.reject(&:blank?) || []

      unless tool_clause_id.present? && checklist_item_id.present?
        respond_to do |format|
          format.html { redirect_back(fallback_location: root_path, alert: "Missing required parameters") }
          format.json { render json: { error: "Missing required parameters" }, status: :unprocessable_entity }
        end
        return
      end

      # Get tool from tool_clause
      tool_clause = ToolClause.find_by(id: tool_clause_id)
      unless tool_clause
        respond_to do |format|
          format.html { redirect_back(fallback_location: root_path, alert: "Tool clause not found") }
          format.json { render json: { error: "Tool clause not found" }, status: :not_found }
        end
        return
      end
      tool = tool_clause.tool

      # Ensure checklist item belongs to this clause (prevents cross-clause assignment)
      unless checklist_item_belongs_to_clause?(tool_clause.clause_id, checklist_item_id)
        respond_to do |format|
          format.html { redirect_back(fallback_location: root_path, alert: "This checkpoint does not belong to the selected clause.") }
          format.json { render json: { error: "This checkpoint does not belong to the selected clause." }, status: :unprocessable_entity }
        end
        return
      end

      success_count = 0
      removed_count = 0
      errors = []

      # Find or create the assessment for this clause + company
      assessment = Assessment.find_or_create_by!(
        tool_clause_id: tool_clause_id,
        company_id: current_company&.id
      )

      assessment_auditor_id = assessment.auditor_user&.id

      ActiveRecord::Base.transaction do
        # Remove users first
        users_to_remove.each do |user_id|
          au = assessment.assessment_users.find_by(user_id: user_id, checklist_item_id: checklist_item_id)
          if au
            if assessment.status == "approved"
              errors << "Cannot remove user from approved assessment"
            elsif au.destroy
              removed_count += 1
              removed_user = User.find_by(id: user_id)
              NotificationService.notify_tool_unassigned(recipient: removed_user, tool: tool, actor: current_user) if removed_user
              AuditLogService.log_action(
                actor_user: current_user,
                company: current_company,
                action: "UNASSIGN_USER_FROM_TOOL_SUBCHECKPOINT",
                entity_type: "assessment",
                entity_id: assessment.id,
                payload: {
                  tool_id: tool.id,
                  tool_name: tool.name,
                  user_id: user_id,
                  tool_clause_id: tool_clause_id,
                  checklist_item_id: checklist_item_id
                }
              )
            else
              errors << "Failed to remove user: #{au.errors.full_messages.join(', ')}"
            end
          end
        end

        # Assign contributors
        contributor_ids.each do |user_id|
          user = User.find_by(id: user_id)
          unless user && current_company && user.company == current_company
            errors << "User #{user_id} not found or doesn't belong to company"
            next
          end

          if assessment_auditor_id && user.id == assessment_auditor_id
            errors << "#{user.name} is the assessment auditor and cannot also be a contributor"
            next
          end

          au = assessment.assessment_users.find_or_initialize_by(
            user_id: user_id,
            checklist_item_id: checklist_item_id
          )
          au.role = "contributor"
          au.assigner_user_id = current_user.id

          if au.save
            success_count += 1
            NotificationService.notify_tool_assigned(recipient: user, assignment: au, actor: current_user)
            AuditLogService.log_action(
              actor_user: current_user,
              company: current_company,
              action: "ASSIGN_USER_TO_TOOL_SUBCHECKPOINT",
              entity_type: "assessment",
              entity_id: assessment.id,
              payload: {
                tool_id: tool.id,
                tool_name: tool.name,
                user_id: user.id,
                user_name: user.name,
                tool_clause_id: tool_clause_id,
                checklist_item_id: checklist_item_id
              }
            )
          else
            errors << "Failed to assign #{user.name}: #{au.errors.full_messages.join(', ')}"
          end
        end
      end

      message_parts = []
      message_parts << "Successfully assigned #{success_count} user(s)" if success_count > 0
      message_parts << "Successfully removed #{removed_count} user(s)" if removed_count > 0
      message_parts << "No changes made" if success_count == 0 && removed_count == 0

      message = message_parts.join(". ")
      message += ". Errors: #{errors.join(', ')}" if errors.any?

      # Get updated user assignments for UI
      updated_users = assessment.assessment_users
        .where(checklist_item_id: checklist_item_id, role: "contributor")
        .includes(:user)

      assigned_users = updated_users.map do |au|
        user = au.user
        {
          id: user&.id,
          name: user&.name,
          status: assessment.status,
          profile_image_url: user&.profile_image&.attached? ? helpers.user_profile_image_url(user) : nil
        }
      end.compact

      respond_to do |format|
        format.html { redirect_back(fallback_location: root_path, notice: message) }
        format.json {
          notification_html = render_to_string(
            partial: "shared/notification",
            locals: { message: message, type: errors.any? ? :warning : :success, animated: true },
            formats: [ :html ]
          )

          render json: {
            success: true,
            message: message,
            assigned: success_count,
            removed: removed_count,
            errors: errors,
            notification_html: notification_html,
            assigned_users: assigned_users,
            status: assessment.status,
            assignment_id: assessment.id
          }
        }
      end
    end

    def get_assignments
      tool_clause_id = params[:tool_clause_id]
      checklist_item_id = params[:checklist_item_id]

      unless tool_clause_id.present? && checklist_item_id.present?
        render json: { error: "Missing parameters" }, status: :unprocessable_entity
        return
      end

      unless current_user&.super_admin? || current_user&.delegated_admin?
        return render(json: { error: "No company context" }, status: :forbidden) unless current_company
      end

      company_id = current_company&.id
      assessment = Assessment.find_by(tool_clause_id: tool_clause_id, company_id: company_id)

      contributors = []
      if assessment
        assessment.assessment_users
          .where(checklist_item_id: checklist_item_id, role: "contributor")
          .includes(:user)
          .each do |au|
            user = au.user
            next unless user
            contributors << {
              id: user.id,
              name: user.name,
              company_role: user.company_user&.role&.gsub("company_", "")&.humanize || "User",
              status: assessment.status,
              profile_image_url: user.profile_image.attached? ? helpers.user_profile_image_url(user) : nil
            }
          end
      end

      render json: {
        contributors: contributors,
        due_date: assessment&.due_date
      }
    end

    def mark_reviewed
      return if prevent_viewer_action
      tool = Tool.find(params[:id])
      locale = params[:language_code].presence || I18n.locale.to_s
      translation = tool.tool_translations.find_by(language_code: locale)

      if translation
        translation.update(needs_review: false, source_updated_at: Time.current)
        redirect_back(fallback_location: tool_path(tool), notice: t("tool_translation_marked_as_reviewed"))
      else
        redirect_back(fallback_location: tool_path(tool), alert: t("tool_translation_not_found"))
      end
    end

    def mark_checkpoint_reviewed
      return if prevent_viewer_action
      checkpoint = ToolCheckpoint.find(params[:checkpoint_id])
      locale = params[:language_code].presence || I18n.locale.to_s
      translation = checkpoint.tool_checkpoint_translations.find_by(language_code: locale)

      if translation
        translation.update(needs_review: false, source_updated_at: Time.current)
        redirect_back(fallback_location: tool_path(checkpoint.tool), notice: t("tool_translation_marked_as_reviewed"))
      else
        redirect_back(fallback_location: tool_path(checkpoint.tool), alert: t("tool_translation_not_found"))
      end
    end

    def mark_subcheckpoint_reviewed
      return if prevent_viewer_action
      subcheckpoint = ToolSubcheckpoint.find(params[:subcheckpoint_id])
      locale = params[:language_code].presence || I18n.locale.to_s
      translation = subcheckpoint.tool_subcheckpoint_translations.find_by(language_code: locale)

      if translation
        translation.update(needs_review: false, source_updated_at: Time.current)
        redirect_back(fallback_location: tool_path(subcheckpoint.tool_checkpoint.tool), notice: t("tool_translation_marked_as_reviewed"))
      else
        redirect_back(fallback_location: tool_path(subcheckpoint.tool_checkpoint.tool), alert: t("tool_translation_not_found"))
      end
    end

    private

    # Ensures the given checklist_item_id belongs to the clause (prevents cross-clause assignment)
    def checklist_item_belongs_to_clause?(clause_id, checklist_item_id)
      return false if clause_id.blank? || checklist_item_id.blank?
      ChecklistItem.exists?(id: checklist_item_id, clause_id: clause_id)
    end
  
    def require_tools_access
      return if current_user&.can_manage_tools?
      redirect_to dashboard_path, alert: "You don't have access to tools.", status: :forbidden
      return
    end

    # Allow company admins to manage assignments for their company (e.g. from standards clause hierarchy).
    def require_tools_or_company_admin_for_assignments
      return if current_user&.can_manage_tools?
      return if current_company && current_user&.company_user&.has_admin_privileges?

      respond_to do |format|
        format.html { redirect_to dashboard_path, alert: "You don't have access to this.", status: :forbidden }
        format.json { render json: { success: false, error: "You don't have access to this." }, status: :forbidden }
      end
      nil
    end

    def process_multiple_choice_options_in_params
      return unless params.dig(:tool, :checkpoints_attributes).present?

      params[:tool][:checkpoints_attributes].each do |cp_index, checkpoint_params|
        next unless checkpoint_params[:subcheckpoints_attributes].present?

        checkpoint_params[:subcheckpoints_attributes].each do |sc_index, subcheckpoint_params|
          next if subcheckpoint_params[:_destroy] == "1"
          next unless subcheckpoint_params[:scoring_type] == "Multiple Choice"

          # Process multiple choice options from nested attributes
          options = []
          if subcheckpoint_params[:multiple_choice_options_attributes].present?
            subcheckpoint_params[:multiple_choice_options_attributes].each do |choice_index, choice_params|
              next if choice_params[:_destroy] == "1"
              next if choice_params[:text].blank?

              options << {
                "text" => choice_params[:text],
                "weight" => choice_params[:weight].to_i
              }
            end
          end

          # Set the multiple_choice_options as an array (Rails will serialize to JSON)
          # Remove the _attributes key so Rails doesn't try to use nested attributes
          subcheckpoint_params.delete(:multiple_choice_options_attributes)
          # Use merge! to ensure the change persists
          subcheckpoint_params.merge!(multiple_choice_options: options)
        end
      end
    end

    def process_multiple_choice_options_on_tool
      return unless params.dig(:tool, :checkpoints_attributes).present?

      # Build a map of checkpoint names to their params
      checkpoint_params_map = {}
      params[:tool][:checkpoints_attributes].each do |cp_index, checkpoint_params|
        next if checkpoint_params[:_destroy] == "1"
        checkpoint_params_map[checkpoint_params[:name]] = checkpoint_params
      end

      # Process each checkpoint in the built tool
      @tool.checkpoints.each do |checkpoint|
        checkpoint_params = checkpoint_params_map[checkpoint.name]
        next unless checkpoint_params
        next unless checkpoint_params[:subcheckpoints_attributes].present?

        # Build a map of subcheckpoint names to their params
        subcheckpoint_params_map = {}
        checkpoint_params[:subcheckpoints_attributes].each do |sc_index, subcheckpoint_params|
          next if subcheckpoint_params[:_destroy] == "1"
          subcheckpoint_params_map[subcheckpoint_params[:name]] = subcheckpoint_params
        end

        # Process each subcheckpoint in the built checkpoint
        checkpoint.subcheckpoints.each do |subcheckpoint|
          next unless subcheckpoint.scoring_type == "Multiple Choice"

          subcheckpoint_params = subcheckpoint_params_map[subcheckpoint.name]
          next unless subcheckpoint_params

          # Process multiple choice options
          if subcheckpoint_params[:multiple_choice_options].present?
            # Already processed by process_multiple_choice_options_in_params
            subcheckpoint.multiple_choice_options = subcheckpoint_params[:multiple_choice_options]
          elsif subcheckpoint_params[:multiple_choice_options_attributes].present?
            # Process from nested attributes
            options = []
            subcheckpoint_params[:multiple_choice_options_attributes].each do |choice_index, choice_params|
              next if choice_params[:_destroy] == "1"
              next if choice_params[:text].blank?
              options << {
                "text" => choice_params[:text],
                "weight" => choice_params[:weight].to_i
              }
            end
            subcheckpoint.multiple_choice_options = options
          end
        end
      end
    end

    def process_business_rules
      return unless params.dig(:tool, :business_rules).present?
      return unless current_user&.can_manage_tools? # Only users with manage_tools permission can set business rules

      business_rules_params = params[:tool][:business_rules]
      rules = []

      if business_rules_params[:rules].present?
        business_rules_params[:rules].each do |index, rule_params|
          next if rule_params[:type].blank?

          rule = {
            "type" => rule_params[:type],
            "description" => rule_params[:description]
          }

          if rule_params[:target_subcheckpoint_id].present?
            rule["target_subcheckpoint_id"] = rule_params[:target_subcheckpoint_id].to_i
          end

          rules << rule
        end
      end

      @tool.business_rules = { "rules" => rules }
    end

    def rebuild_nested_attributes_from_params
      # Rails should automatically build nested attributes from tool_params,
      # but this method ensures they're properly built if something goes wrong
      return unless params[:tool][:checkpoints_attributes].present?
      return if @tool.checkpoints.any? # Already built by Rails

      checkpoints_params = params[:tool][:checkpoints_attributes]
      checkpoints_params.each do |index, checkpoint_params|
        next if checkpoint_params[:_destroy] == "1"

        checkpoint = @tool.checkpoints.build(name: checkpoint_params[:name])

        if checkpoint_params[:subcheckpoints_attributes].present?
          checkpoint_params[:subcheckpoints_attributes].each do |sc_index, subcheckpoint_params|
            next if subcheckpoint_params[:_destroy] == "1"

            subcheckpoint = checkpoint.subcheckpoints.build(
              name: subcheckpoint_params[:name],
              description: subcheckpoint_params[:description],
              scoring_type: subcheckpoint_params[:scoring_type],
              min_score: subcheckpoint_params[:min_score],
              max_score: subcheckpoint_params[:max_score]
            )

            # Handle multiple choice options
            if subcheckpoint_params[:scoring_type] == "Multiple Choice"
              if subcheckpoint_params[:multiple_choice_options].present?
                subcheckpoint.multiple_choice_options = subcheckpoint_params[:multiple_choice_options]
              elsif subcheckpoint_params[:multiple_choice_options_attributes].present?
                # Process from nested attributes if not already processed
                options = []
                subcheckpoint_params[:multiple_choice_options_attributes].each do |choice_index, choice_params|
                  next if choice_params[:_destroy] == "1"
                  next if choice_params[:text].blank?
                  options << {
                    "text" => choice_params[:text],
                    "weight" => choice_params[:weight].to_i
                  }
                end
                subcheckpoint.multiple_choice_options = options
              end
            end
          end
        end
      end
    end

    def tool_params
      params.require(:tool).permit(
        :name,
        :description,
        business_rules: {},
        checkpoints_attributes: [
          :id,
          :name,
          :_destroy,
          subcheckpoints_attributes: [
            :id,
            :name,
            :description,
            :scoring_type,
            :min_score,
            :max_score,
            :weight,
            :is_cap,
            { multiple_choice_options: [ :text, :weight ] },
            :_destroy,
            multiple_choice_options_attributes: [
              :index,
              :text,
              :weight,
              :_destroy
            ]
          ]
        ]
      )
    end

    # Invalidate clause score caches for all companies assigned to affected standards so company
    # standard score (compliance) is recalculated after tool update / clause link changes.
    def invalidate_company_score_cache_for_tool_changes(affected_clause_ids:, business_rules_only: false)
      return if affected_clause_ids.blank?

      roots_by_standard = {}
      Clause.where(id: affected_clause_ids).find_each do |clause|
        root = clause
        root = root.parent while root.parent.present?
        standard = root.standard_version&.standard
        next unless standard

        roots_by_standard[standard] ||= []
        roots_by_standard[standard] << root unless roots_by_standard[standard].include?(root)
      end

      roots_by_standard.each do |standard, roots|
        ClauseScorePropagator.invalidate_cache_for_tool_clause_changes(standard, roots)
      end
    end

    # Recursively get all terminal (leaf) clauses under a given clause
    def get_all_terminal_clauses(clause)
      if clause.leaf?
        [ clause ]
      else
        clause.children.flat_map { |child| get_all_terminal_clauses(child) }
      end
    end

    def load_company_users
      if current_company
        @company_users = current_company.company_users.includes(:user).order("users.name")
      else
        @company_users = CompanyUser.none
      end
    end

    def synchronize_tool_translations(tool)
      tool.reload
      source_locale = I18n.locale.to_s
      upsert_source_tool_translations(tool, source_locale)
      auto_translate_tool_content(tool, source_locale)
    end

    def upsert_source_tool_translations(tool, source_locale)
      tool_translation = tool.tool_translations.find_or_initialize_by(language_code: source_locale)
      tool_translation.name = tool.name
      tool_translation.description = tool.description
      tool_translation.needs_review = false
      tool_translation.ai_generated = false
      tool_translation.save!

      tool.checkpoints.each do |checkpoint|
        checkpoint_translation = checkpoint.tool_checkpoint_translations.find_or_initialize_by(language_code: source_locale)
        checkpoint_translation.name = checkpoint.name
        checkpoint_translation.needs_review = false
        checkpoint_translation.ai_generated = false
        checkpoint_translation.save!

        checkpoint.subcheckpoints.each do |subcheckpoint|
          subcheckpoint_translation = subcheckpoint.tool_subcheckpoint_translations.find_or_initialize_by(language_code: source_locale)
          subcheckpoint_translation.name = subcheckpoint.name
          subcheckpoint_translation.description = subcheckpoint.description
          subcheckpoint_translation.multiple_choice_options = normalize_multiple_choice_options(subcheckpoint.multiple_choice_options)
          subcheckpoint_translation.needs_review = false
          subcheckpoint_translation.ai_generated = false
          subcheckpoint_translation.save!
        end
      end
    end

    def auto_translate_tool_content(tool, source_locale)
      supported_locales = %w[en ar]
      target_locales = supported_locales - [ source_locale ]
      target_locales.each do |target_locale|
        translate_tool_record(tool, source_locale, target_locale)
        tool.checkpoints.each do |checkpoint|
          translate_checkpoint_record(checkpoint, source_locale, target_locale)
          checkpoint.subcheckpoints.each do |subcheckpoint|
            translate_subcheckpoint_record(subcheckpoint, source_locale, target_locale)
          end
        end
      end
    end

    def translate_tool_record(tool, source_locale, target_locale)
      translated_name = translate_text_with_ollama(tool.name, source_locale, target_locale)
      translated_description = translate_text_with_ollama(tool.description, source_locale, target_locale)
      translation = tool.tool_translations.find_or_initialize_by(language_code: target_locale)

      attrs = {
        name: translated_name.presence || "[Translation needed]",
        description: translated_description.presence || "[Translation needed]",
        needs_review: true,
        ai_generated: true,
        source_updated_at: Time.current,
        last_modified_at: Time.current
      }

      persist_auto_translation(translation, attrs)
    end

    def translate_checkpoint_record(checkpoint, source_locale, target_locale)
      translated_name = translate_text_with_ollama(checkpoint.name, source_locale, target_locale)
      translation = checkpoint.tool_checkpoint_translations.find_or_initialize_by(language_code: target_locale)

      attrs = {
        name: translated_name.presence || "[Translation needed]",
        needs_review: true,
        ai_generated: true,
        source_updated_at: Time.current,
        last_modified_at: Time.current
      }

      persist_auto_translation(translation, attrs)
    end

    def translate_subcheckpoint_record(subcheckpoint, source_locale, target_locale)
      translated_name = translate_text_with_ollama(subcheckpoint.name, source_locale, target_locale)
      translated_description = translate_text_with_ollama(subcheckpoint.description, source_locale, target_locale)
      translated_options = normalize_multiple_choice_options(subcheckpoint.multiple_choice_options).map do |option|
        translated_text = translate_text_with_ollama(option["text"], source_locale, target_locale)
        option.merge("text" => translated_text.presence || "[Translation needed]")
      end

      translation = subcheckpoint.tool_subcheckpoint_translations.find_or_initialize_by(language_code: target_locale)
      attrs = {
        name: translated_name.presence || "[Translation needed]",
        description: translated_description.presence || "[Translation needed]",
        multiple_choice_options: translated_options,
        needs_review: true,
        ai_generated: true,
        source_updated_at: Time.current,
        last_modified_at: Time.current
      }

      persist_auto_translation(translation, attrs)
    end

    def persist_auto_translation(record, attrs)
      if record.new_record?
        record.assign_attributes(attrs)
        record.save!
      else
        record.update_columns(attrs)
      end
    end

    def normalize_multiple_choice_options(options)
      return [] unless options.is_a?(Array)

      options.map do |option|
        next unless option.is_a?(Hash)

        {
          "text" => (option["text"] || option[:text]).to_s,
          "weight" => (option["weight"] || option[:weight]).to_i
        }
      end.compact
    end

    def translate_text_with_ollama(text, source_language, target_language)
      return nil if text.blank?

      language_names = {
        "en" => "English",
        "ar" => "Arabic"
      }

      source_name = language_names[source_language] || source_language
      target_name = language_names[target_language] || target_language

      prompt = <<~PROMPT
        You are a strict translation engine.
        Translate from #{source_name} to #{target_name}.

        RULES:
        - Return ONLY the translation.
        - No explanations, notes, alternatives, or quotes.
        - Preserve technical meaning and terms.
        - Keep output in #{target_name} only.
        - Keep placeholders/identifiers unchanged.

        SOURCE:
        #{text}
      PROMPT

      ollama_url = ENV.fetch("OLLAMA_URL", "http://localhost:11434")
      model = ENV.fetch("TRANSLATION_OLLAMA_MODEL", "qwen2.5:14b-instruct")
      client = OllamaClient.new(model: model, base_url: ollama_url)
      translated = client.generate(prompt, max_tokens: 500)
      translated = translated.to_s.strip
      translated = translated.gsub(/^```json\s*/, "").gsub(/\s*```$/, "")
      translated = translated.gsub(/^```\s*/, "").gsub(/\s*```$/, "")
      translated = translated.gsub(/^["']|["']$/, "")
      sanitize_translation_output(translated, target_language).presence
    rescue => e
      Rails.logger.error "Tool translation error: #{e.message}"
      nil
    end

    def sanitize_translation_output(text, target_language)
      cleaned = text.to_s.gsub(/\r/, "\n").strip
      return "" if cleaned.blank?

      # Drop obvious meta lines from chatty model responses.
      cleaned_lines = cleaned.lines.map(&:strip).reject(&:blank?).reject do |line|
        line.match?(/\A(?:note|please note|translation|correct translation|sorry|my mistake)/i) ||
          line.match?(/\A(?:ملاحظة|يرجى الملاحظة|الترجمة الصحيحة|خطأ|تصحيح)/)
      end
      cleaned = cleaned_lines.join("\n")

      extracted = if target_language.to_s == "ar"
        # Keep Arabic content and common punctuation only.
        cleaned.scan(/[\p{Arabic}\p{N}\s\.,،؛:%\-\(\)\/]+/).join(" ")
      else
        # Keep latin/alphanumeric content and common punctuation only.
        cleaned.scan(/[A-Za-z0-9\s\.,;:%\-\(\)\/'"]+/).join(" ")
      end

      extracted = extracted.gsub(/\s+/, " ").strip
      return extracted if extracted.present?

      # Last-resort fallback if regex stripping removed everything.
      cleaned.split("\n").map(&:strip).find(&:present?).to_s
    end
end
