class Dashboard::CapaManagementController < Dashboard::BaseController
  before_action :ensure_company_selected, except: [ :select_company, :set_company ]
  before_action :prevent_viewer_action

  helper_method :can_create_capa?, :can_manage_capa?, :can_close_capa?, :can_link_documents_to_capa?, :assignee_of_capa_action?, :can_view_capa_activity_log?, :can_link_documents_to_capa_action?, :can_upload_evidence_to_capa_action?, :can_update_capa_action?, :can_delete_capa_action_comment?, :capa_actions_visible_to_current_user, :can_assign_to_capa_action?

  # Allow viewers to access read-only actions
  skip_before_action :prevent_viewer_action, only: [ :show, :show_capa_action, :overview, :export, :select_company, :set_company, :list, :board, :archives ]

  def select_company
    unless current_user&.platform_admin?
      redirect_to dashboard_capa_management_path, alert: "You don't have permission to select companies."
      return
    end

    @companies = Company.active.order(:name)
  end

  def set_company
    unless current_user&.platform_admin?
      redirect_to dashboard_capa_management_path, alert: "You don't have permission to select companies."
      return
    end

    company = Company.active.find_by(id: params[:company_id])

    if company
      session[:company_id] = company.id
      redirect_to dashboard_capa_management_path, notice: "Switched to #{company.name}"
    else
      redirect_to select_company_dashboard_capa_management_path, alert: "Company not found"
    end
  end

  def export
    unless current_company
      redirect_to dashboard_capa_management_path, alert: "Company not selected" and return
    end

    language = params[:language] || "en"
    language = "en" unless [ "en", "ar" ].include?(language)

    capas = capa_visible_scope(
      base: Capa.where(company_id: current_company.id)
                .includes(:standard, :company_users, :users, capa_actions: { company_users: :user })
    )

    archived_state = params[:archived_state].presence || "active"
    capas = case archived_state
    when "archived"
              capas.archived
    when "all"
              capas
    else
              capas.not_archived
    end

    status_filter = params[:status].presence
    if status_filter && status_filter != "all"
      if status_filter == "overdue"
        capas = capas.where("due_date < ?", Date.today)
                     .where.not(status: :closed)
                     .where.not(due_date: nil)
      else
        capas = capas.where(status: status_filter)
      end
    end

    if params[:priority].present?
      capas = capas.where(priority: params[:priority])
    end

    if params[:due_date_from].present?
      capas = capas.where("due_date >= ?", params[:due_date_from])
    end

    if params[:due_date_to].present?
      capas = capas.where("due_date <= ?", params[:due_date_to])
    end

    assignee_ids = Array(params[:assignee_ids]).reject(&:blank?)
    if assignee_ids.any?
      capas = capas.joins(:capa_assignments)
                   .where(capa_assignments: { company_user_id: assignee_ids })
                   .distinct
    end

    capas = capas.order(created_at: :desc)

    # Generate ZIP containing CSVs using service
    service = CapaExportService.new(capas, language)
    zip_data = service.generate_zip
    
    send_data zip_data, 
              type: 'application/zip',
              disposition: 'attachment',
              filename: service.filename
  end

  def overview
    @standards = if current_company
      Standard.joins(:company_standards)
              .where(company_standards: { company_id: current_company.id, status: "active" })
              .distinct
    else
      Standard.none
    end
    @capas = if current_company
      capa_visible_scope(base: Capa.where(company_id: current_company.id).not_archived)
          .includes(:standard, :company_users, :users)
          .order('capas.created_at DESC')
    else
      Capa.none
    end
    # Filter company users by current company
    if current_company
      @company_users = current_company.company_users.includes(:user).all
    else
      @company_users = CompanyUser.none
    end

    # Get CAPAs assigned to current user (within visible scope)
    visible_base = current_company ? capa_visible_scope(base: Capa.where(company_id: current_company.id).not_archived) : Capa.none
    @assigned_to_me_capas = if current_user&.company_user && current_company
      visible_base.joins(:capa_assignments)
          .where(capa_assignments: { company_user_id: current_user.company_user.id })
          .includes(:standard, :company_users, :users)
          .order(due_date: :asc)
          .order('capas.created_at DESC')
          .limit(4)
          .distinct
    else
      Capa.none
    end

    # Get overdue CAPAs visible to current user
    @overdue_capas = if current_company
      capa_visible_scope(base: Capa.where(company_id: current_company.id)
          .where("due_date < ?", Date.today)
          .where.not(status: :closed)
          .where.not(due_date: nil)
          .not_archived)
          .includes(:standard, :company_users, :users)
          .order(due_date: :asc)
          .order('capas.created_at DESC')
          .limit(4)
    else
      Capa.none
    end

    # Get top users by CAPA assignment count (within visible CAPAs)
    visible_ids = current_company ? capa_visible_scope(base: Capa.where(company_id: current_company.id).not_archived).select(:id) : Capa.none
    @top_assigned_users = if current_company
      CompanyUser.joins(:capa_assignments)
                 .where(capa_assignments: { capa_id: visible_ids })
                 .group("company_users.id")
                 .select("company_users.*, COUNT(capa_assignments.id) as assignment_count")
                 .order("assignment_count DESC")
                 .limit(4)
                 .includes(:user)
                 .map do |company_user|
                   {
                     company_user: company_user,
                     count: company_user.read_attribute(:assignment_count).to_i
                   }
                 end
    else
      []
    end

    # Get CAPA status breakdown for pie chart (visible CAPAs only)
    @status_breakdown = if current_company
      capa_visible_scope(base: Capa.where(company_id: current_company.id).not_archived)
          .group(:status)
          .count
    else
      {}
    end

    # Get CAPAs over time for column chart (last 7 days, visible only)
    @capa_over_time = if current_company
      seven_days_ago = 7.days.ago.beginning_of_day
      visible_base = capa_visible_scope(base: Capa.where(company_id: current_company.id).not_archived.where("capas.created_at >= ?", seven_days_ago))

      total_by_date = visible_base
                          .group(Arel.sql("DATE(capas.created_at)"))
                          .count
                          .transform_keys { |date| date.is_a?(Date) ? date.strftime("%b %d") : Date.parse(date.to_s).strftime("%b %d") }

      closed_by_date = visible_base
                          .where(status: "closed")
                          .group(Arel.sql("DATE(capas.created_at)"))
                          .count
                          .transform_keys { |date| date.is_a?(Date) ? date.strftime("%b %d") : Date.parse(date.to_s).strftime("%b %d") }

      # Combine into Chartkick format for multiple series
      all_dates = (7.days.ago.to_date..Date.today).map { |d| d.strftime("%b %d") }

      # Format data for Chartkick multiple series (array format)
      closed_data = all_dates.map { |date_label| [ date_label, closed_by_date[date_label] || 0 ] }.to_h
      total_data = all_dates.map { |date_label| [ date_label, total_by_date[date_label] || 0 ] }.to_h

      chart_data = [
        { name: "Closed CAPA", data: closed_data },
        { name: "Total CAPA", data: total_data }
      ]
      chart_data
    else
      []
    end
  end

  def show
    @capa = if current_company
      capa_visible_scope(
        base: Capa.where(company_id: current_company.id)
                  .includes(:standard, :company_users, :users, :questionnaire, evidence_attachments: [ :upload, :attached_by_user ], clauses: [ :standard_version, :parent, { standard_version: :standard }, { checklist_items: :checklist_item_translations } ], capa_actions: { company_users: :user })
      ).find_by(id: params[:id])
    else
      nil
    end

    unless @capa
      redirect_to dashboard_capa_management_list_path, alert: "CAPA not found"
      return
    end

    # Determine if current user can see the activity log for this CAPA
    @can_view_activity_log = can_view_capa_activity_log?(@capa)

    # For contributor/auditor: only actions assigned to them; for admin/QM: all actions
    @capa_actions_visible = capa_actions_visible_to_current_user(@capa)

    # Load activities for the activity log (using audit logs) only when allowed
    @activities = if @can_view_activity_log
      AuditLog.for_capa_with_actions(@capa).includes(:actor_user).order(created_at: :desc, id: :desc)
    else
      []
    end

    # Load company users and standards for edit modal
    if current_company
      @company_users = current_company.company_users.includes(:user).all
    else
      @company_users = CompanyUser.none
    end
    @standards = if current_company
      Standard.joins(:company_standards)
              .where(company_standards: { company_id: current_company.id, status: "active" })
              .distinct
    else
      Standard.none
    end

    # Folders for upload dialog (company-scoped; evidence tab renders library upload dialog)
    @folders_for_upload = @capa.company_id.present? ? Folder.where(company_id: @capa.company_id).where.not(company_id: nil).order(:name) : Folder.none
  end

  def list
    # Get CAPAs visible to current user (role-based: contributor=assigned, auditor=assigned/created, QM/Admin=all)
    @capas = if current_company
      capa_visible_scope(base: Capa.where(company_id: current_company.id).not_archived)
          .includes(:standard, :company_users, :users)
          .order(created_at: :desc)
    else
      Capa.none
    end

    # Apply search filter
    if params[:search].present?
      query = "%#{params[:search]}%"
      @capas = @capas.where("title ILIKE :q OR description ILIKE :q", q: query)
    end

    # Apply status filter
    if params[:status].present? && params[:status] != "all"
      if params[:status] == "overdue"
        @capas = @capas.where("due_date < ?", Date.today).where.not(status: :closed).where.not(due_date: nil)
      else
        @capas = @capas.where(status: params[:status])
      end
    end

    # Apply priority filter
    if params[:priority].present?
      @capas = @capas.where(priority: params[:priority])
    end

    # Apply due date filter
    if params[:due_date_from].present?
      @capas = @capas.where("due_date >= ?", params[:due_date_from])
    end
    if params[:due_date_to].present?
      @capas = @capas.where("due_date <= ?", params[:due_date_to])
    end

    # Apply assignee filter
    if params[:assignee_id].present?
      @capas = @capas.joins(:capa_assignments)
                     .where(capa_assignments: { company_user_id: params[:assignee_id] })
                     .distinct
    end

    # Load company users for assignee filter and modal
    if current_company
      @company_users = current_company.company_users.includes(:user).all
    else
      @company_users = CompanyUser.none
    end

    # Load standards for new/edit action modal
    @standards = if current_company
      Standard.joins(:company_standards)
              .where(company_standards: { company_id: current_company.id, status: "active" })
              .distinct
    else
      Standard.none
    end
  end

  def board
    @capas = if current_company
      capa_visible_scope(base: Capa.where(company_id: current_company.id).not_archived)
          .includes(:standard, :company_users, :users, :capa_actions)
    else
      Capa.none
    end

    if params[:search].present?
      query = "%#{params[:search]}%"
      @capas = @capas.where("title ILIKE :q OR description ILIKE :q", q: query)
    end

    # Load company users for assignment in modal
    if current_company
      @company_users = current_company.company_users.includes(:user).all
    else
      @company_users = CompanyUser.none
    end

    # Load standards for modal select
    @standards = if current_company
      Standard.joins(:company_standards)
              .where(company_standards: { company_id: current_company.id, status: "active" })
              .distinct
    else
      Standard.none
    end
  end

  def archives
    # Get archived CAPAs visible to current user
    @capas = if current_company
      capa_visible_scope(base: Capa.where(company_id: current_company.id).archived)
          .includes(:standard, :company_users, :users)
          .order(created_at: :desc)
    else
      Capa.none
    end

    # Apply search filter
    if params[:search].present?
      query = "%#{params[:search]}%"
      @capas = @capas.where("title ILIKE :q OR description ILIKE :q", q: query)
    end

    # Apply status filter
    if params[:status].present? && params[:status] != "all"
      if params[:status] == "overdue"
        @capas = @capas.where("due_date < ?", Date.today).where.not(status: :closed).where.not(due_date: nil)
      else
        @capas = @capas.where(status: params[:status])
      end
    end

    # Apply priority filter
    if params[:priority].present?
      @capas = @capas.where(priority: params[:priority])
    end

    # Apply due date filter
    if params[:due_date_from].present?
      @capas = @capas.where("due_date >= ?", params[:due_date_from])
    end
    if params[:due_date_to].present?
      @capas = @capas.where("due_date <= ?", params[:due_date_to])
    end

    # Apply assignee filter
    if params[:assignee_id].present?
      @capas = @capas.joins(:capa_assignments)
                     .where(capa_assignments: { company_user_id: params[:assignee_id] })
                     .distinct
    end

    # Load company users for assignee filter and modal
    if current_company
      @company_users = current_company.company_users.includes(:user).all
    else
      @company_users = CompanyUser.none
    end

    # Load standards for new/edit action modal
    @standards = if current_company
      Standard.joins(:company_standards)
              .where(company_standards: { company_id: current_company.id, status: "active" })
              .distinct
    else
      Standard.none
    end
  end

  def create
    unless current_company
      render json: { message: "No current company context found" }, status: :unprocessable_entity and return
    end
    unless can_create_capa?
      render json: { message: "You do not have permission to create CAPAs. Only Auditors, QM and Company Admins can create CAPAs." }, status: :forbidden and return
    end
    # Get company user IDs before filtering params
    company_user_ids = params[:capa][:company_user_ids] if params[:capa][:company_user_ids].present?
    # Always use manual analysis method
    analysis_method = "manual"

    # Get permitted params and filter out non-database attributes
    capa_params_filtered = capa_params
    # Remove attributes that don't exist in the database
    capa_params_filtered = capa_params_filtered.except(:company_user_ids)
    # Convert empty string to nil for standard_id and due_date
    capa_params_filtered[:standard_id] = nil if capa_params_filtered[:standard_id].blank?
    capa_params_filtered[:due_date] = nil if capa_params_filtered[:due_date].blank?
    capa_params_filtered[:analysis_method] = analysis_method

    @capa = Capa.new(capa_params_filtered)
    @capa.company_id = current_company.id
    @capa.created_by_id = current_user.id

    if @capa.save
      # Create CAPA assignments for selected company users (only from current company)
      allowed_ids = allowed_company_user_ids_for_capa(company_user_ids)
      if allowed_ids.present?
        # Get users for activity logging
        added_users = CompanyUser.where(id: allowed_ids).includes(:user).map(&:user)

        # Create assignments
        allowed_ids.each do |company_user_id|
          CapaAssignment.create(capa: @capa, company_user_id: company_user_id)
        end

        # Sync status with assignments (will automatically set to "assigned" if status is "open")
        @capa.sync_status_with_assignments

        # Log audit actions and create notifications for each assigned user
        added_users.each do |user|
          AuditLogService.log_action(
            actor_user: current_user,
            company: current_company,
            action: "ASSIGN_USER_TO_CAPA",
            entity_type: "capa",
            entity_id: @capa.id,
            payload: {
              user_id: user.id,
              user_name: user.name
            }
          )
          NotificationService.notify_capa_assigned(recipient: user, capa: @capa, actor: current_user)
        end
      end

      # Reload to get associations
      @capa.reload

      # Log audit action
      AuditLogService.log_action(
        actor_user: current_user,
        company: current_company,
        action: "CREATE_CAPA",
        entity_type: "capa",
        entity_id: @capa.id,
        payload: {
          title: @capa.title,
          status: @capa.status,
          priority: @capa.priority,
          analysis_method: analysis_method
        }
      )

      # Preload associations for rendering (including nested user association)
      ActiveRecord::Associations::Preloader.new(
        records: [ @capa ],
        associations: { company_users: :user, standard: {} }
      ).call

      notification_html = render_to_string(partial: "shared/notification", locals: { message: "CAPA created successfully!", type: :success, animated: true }, formats: [ :html ])

      # Calculate overview statistics
      overview_stats = calculate_overview_statistics

      # Get table rows if CAPA appears in overview tables
      assigned_to_me_row = get_assigned_to_me_capa_row(@capa)
      overdue_row = get_overdue_capa_row(@capa)

      # Get assignees data (first 3 for display)
      assignees = @capa.company_users.includes(:user).limit(3).map do |cu|
        {
          id: cu.id,
          name: cu.user.name,
          initial: cu.user.name[0].upcase
        }
      end

      render json: {
        message: "CAPA created successfully!",
        capa_id: @capa.id,
        notification_html: notification_html,
        overview_stats: overview_stats,
        assigned_to_me_row: assigned_to_me_row,
        overdue_row: overdue_row,
        capa: {
          id: @capa.id,
          friendly_id: @capa.friendly_id,
          friendly_code: @capa.friendly_code,
          title: @capa.title,
          description: @capa.description,
          status: @capa.status,
          priority: @capa.priority,
          due_date: @capa.due_date&.strftime("%Y-%m-%d"),
          source: @capa.source,
          standard_id: @capa.standard_id,
          assignee_ids: @capa.company_users.pluck(:id).join(",")
        },
        assignees: assignees,
        total_assignees: @capa.company_users.count,
        standard_display_name: @capa.standard&.display_name
      }, status: :created
    else
      error_message = @capa.errors.full_messages.join(", ")
      notification_html = render_to_string(partial: "shared/notification", locals: { message: error_message, type: :error, animated: true }, formats: [ :html ])
      render json: { message: error_message, notification_html: notification_html }, status: :unprocessable_entity
    end
  end

  def destroy
    capa = current_company ? capa_visible_scope(base: Capa.where(company_id: current_company.id)).find_by(id: params[:id]) : nil

    unless capa
      if request.format.json?
        notification_html = render_to_string(partial: "shared/notification", locals: { message: "CAPA not found", type: :error, animated: true }, formats: [ :html ])
        render json: { error: "CAPA not found", notification_html: notification_html }, status: :not_found and return
      else
        redirect_back fallback_location: dashboard_capa_management_list_path, alert: "CAPA not found" and return
      end
    end
    unless can_manage_capa?(capa)
      if request.format.json?
        notification_html = render_to_string(partial: "shared/notification", locals: { message: "You do not have permission to delete this CAPA.", type: :error, animated: true }, formats: [ :html ])
        render json: { error: "You do not have permission to delete this CAPA.", notification_html: notification_html }, status: :forbidden and return
      else
        redirect_back fallback_location: dashboard_capa_management_list_path, alert: "You do not have permission to delete this CAPA." and return
      end
    end

    capa_id = capa.id
    capa_title = capa.title
    capa.destroy

    # Log audit action
    AuditLogService.log_action(
      actor_user: current_user,
      company: current_company,
      action: "DELETE_CAPA",
      entity_type: "capa",
      entity_id: capa_id,
      payload: { title: capa_title }
    )

    if request.format.json?
      notification_html = render_to_string(partial: "shared/notification", locals: { message: "CAPA deleted successfully", type: :success, animated: true }, formats: [ :html ])
      render json: { message: "CAPA deleted successfully", id: capa_id, notification_html: notification_html }
    else
      redirect_back fallback_location: dashboard_capa_management_list_path, notice: "CAPA deleted"
    end
  end

  def update_status
    capa = current_company ? capa_visible_scope(base: Capa.where(company_id: current_company.id)).find_by(id: params[:id]) : nil

    unless capa
      error_message = I18n.t("capa_management_ui.notifications.capa_not_found")
      notification_html = render_to_string(partial: "shared/notification", locals: { message: error_message, type: :error, animated: true }, formats: [ :html ])
      render json: { error: error_message, notification_html: notification_html }, status: :not_found and return
    end

    # Only company admin or QM (in same company as CAPA) can set CAPA to Closed
    if params[:status] == "closed" && !can_close_capa?(capa)
      error_message = "Only Quality Managers and Company Admins can close a CAPA."
      notification_html = render_to_string(partial: "shared/notification", locals: { message: error_message, type: :error, animated: true }, formats: [ :html ])
      render json: { error: error_message, notification_html: notification_html }, status: :forbidden and return
    end

    # Contributors cannot set CAPA status to Open
    if params[:status] == "open" && current_user&.company_user&.company_contributor?
      error_message = "You do not have permission to set this CAPA to Open."
      notification_html = render_to_string(partial: "shared/notification", locals: { message: error_message, type: :error, animated: true }, formats: [ :html ])
      render json: { error: error_message, notification_html: notification_html }, status: :forbidden and return
    end

    # Reverting to Open (from Assigned) removes all assignees; only QM, company admin, or auditor who created this CAPA can do it (company-scoped)
    if params[:status] == "open" && capa.status == "assigned" && !can_revert_assigned_to_open?(capa)
      error_message = "Only the Quality Manager, Company Admin, or the Auditor who created this CAPA can revert it to Open (which removes all assignees)."
      notification_html = render_to_string(partial: "shared/notification", locals: { message: error_message, type: :error, animated: true }, formats: [ :html ])
      render json: { error: error_message, notification_html: notification_html }, status: :forbidden and return
    end

    permitted_statuses = Capa.statuses.keys
    new_status = params[:status]
    unless permitted_statuses.include?(new_status)
      notification_html = render_to_string(partial: "shared/notification", locals: { message: "Invalid status", type: :error, animated: true }, formats: [ :html ])
      render json: { error: "Invalid status", notification_html: notification_html }, status: :unprocessable_entity and return
    end

    assignment_notice = nil
    old_status = capa.status

    ActiveRecord::Base.transaction do
      capa.update!(status: new_status)
      assignment_notice = handle_assigned_to_open_transition!(capa, old_status, capa.status)
    end
    capa.reload

    # Log audit action
    AuditLogService.log_action(
      actor_user: current_user,
      company: current_company,
      action: "UPDATE_CAPA_STATUS",
      entity_type: "capa",
      entity_id: capa.id,
      payload: { old_status: old_status, new_status: capa.status }
    )

    response_payload = { id: capa.id, status: capa.status }
    if assignment_notice
      notification_html = render_to_string(
        partial: "shared/notification",
        locals: { message: assignment_notice, type: :success, animated: true },
        formats: [ :html ]
      )
      response_payload[:notification_html] = notification_html
    end

    render json: response_payload
  rescue ActiveRecord::RecordInvalid => e
    error_message = e.record.errors.full_messages.join(", ")
    notification_html = render_to_string(partial: "shared/notification", locals: { message: error_message, type: :error, animated: true }, formats: [ :html ])
    render json: { error: error_message, notification_html: notification_html }, status: :unprocessable_entity
  end

  def update
    capa = current_company ? capa_visible_scope(base: Capa.where(company_id: current_company.id)).find_by(id: params[:id]) : nil
    unless capa
      error_message = I18n.t("capa_management_ui.notifications.capa_not_found")
      notification_html = render_to_string(partial: "shared/notification", locals: { message: error_message, type: :error, animated: true }, formats: [ :html ])
      render json: { error: error_message, notification_html: notification_html }, status: :not_found and return
    end
    unless can_manage_capa?(capa)
      error_message = "You do not have permission to edit this CAPA."
      notification_html = render_to_string(partial: "shared/notification", locals: { message: error_message, type: :error, animated: true }, formats: [ :html ])
      render json: { error: error_message, notification_html: notification_html }, status: :forbidden and return
    end

    permitted = capa_params
    permitted[:standard_id] = nil if permitted[:standard_id].blank?
    permitted[:due_date] = nil if permitted[:due_date].blank?

    if permitted[:status].present?
      unless Capa.statuses.keys.include?(permitted[:status])
        notification_html = render_to_string(partial: "shared/notification", locals: { message: "Invalid status", type: :error, animated: true }, formats: [ :html ])
        render json: { error: "Invalid status", notification_html: notification_html }, status: :unprocessable_entity and return
      end
    end

    assignment_notice = nil
    old_status = capa.status

    ActiveRecord::Base.transaction do
      capa.update!(permitted)
      # Sync assignments if provided (including empty array to clear all assignments)
      if params[:capa] && params[:capa].key?(:company_user_ids)
        new_ids = Array(params[:capa][:company_user_ids]).reject(&:blank?).map(&:to_s)
        new_ids = allowed_company_user_ids_for_capa(new_ids).map(&:to_s).uniq
        current_ids = capa.capa_assignments.pluck(:company_user_id).map(&:to_s)
        to_add = new_ids - current_ids
        to_remove = current_ids - new_ids

        # Get users for activity logging
        added_users = CompanyUser.where(id: to_add).includes(:user).map(&:user)
        removed_users = CompanyUser.where(id: to_remove).includes(:user).map(&:user)

        # Create and remove assignments
        to_add.each { |cid| CapaAssignment.create!(capa: capa, company_user_id: cid) }
        CapaAssignment.where(capa: capa, company_user_id: to_remove).delete_all if to_remove.any?

        # Sync status with assignments (needed because delete_all doesn't trigger callbacks)
        capa.sync_status_with_assignments if to_add.any? || to_remove.any?

        # Log audit actions and create notifications for assigned users
        added_users.each do |user|
          AuditLogService.log_action(
            actor_user: current_user,
            company: current_company,
            action: "ASSIGN_USER_TO_CAPA",
            entity_type: "capa",
            entity_id: capa.id,
            payload: {
              user_id: user.id,
              user_name: user.name
            }
          )
          NotificationService.notify_capa_assigned(recipient: user, capa: capa, actor: current_user)
        end

        # Log audit actions and create notifications for unassigned users
        removed_users.each do |user|
          AuditLogService.log_action(
            actor_user: current_user,
            company: current_company,
            action: "UNASSIGN_USER_FROM_CAPA",
            entity_type: "capa",
            entity_id: capa.id,
            payload: {
              user_id: user.id,
              user_name: user.name
            }
          )
          NotificationService.notify_capa_unassigned(recipient: user, capa: capa, actor: current_user)
        end
      end

      assignment_notice = handle_assigned_to_open_transition!(capa, old_status, capa.status)
    end

    if capa.errors.empty?
      # Reload to get updated associations
      capa.reload

      # Audit logging is handled by the model's after_update callback

      # Preload associations for rendering (including nested user association)
      ActiveRecord::Associations::Preloader.new(
        records: [ capa ],
        associations: { company_users: :user, standard: {} }
      ).call

      message = "CAPA updated successfully"
      message += " #{assignment_notice}" if assignment_notice
      notification_html = render_to_string(partial: "shared/notification", locals: { message: message.strip, type: :success, animated: true }, formats: [ :html ])

      # Calculate overview statistics
      overview_stats = calculate_overview_statistics

      # Get table rows if CAPA appears in overview tables
      assigned_to_me_row = get_assigned_to_me_capa_row(capa)
      overdue_row = get_overdue_capa_row(capa)

      # Generate show page detail HTML
      show_page_html = generate_show_page_html(capa)

      # Get assignees data (first 3 for display)
      assignees = capa.company_users.includes(:user).limit(3).map do |cu|
        {
          id: cu.id,
          name: cu.user.name,
          initial: cu.user.name[0].upcase
        }
      end

      render json: {
        id: capa.id,
        notification_html: notification_html,
        overview_stats: overview_stats,
        assigned_to_me_row: assigned_to_me_row,
        overdue_row: overdue_row,
        show_page_html: show_page_html,
        capa: {
          id: capa.id,
          friendly_id: capa.friendly_id,
          friendly_code: capa.friendly_code,
          title: capa.title,
          description: capa.description,
          status: capa.status,
          priority: capa.priority,
          due_date: capa.due_date&.strftime("%Y-%m-%d"),
          source: capa.source,
          standard_id: capa.standard_id,
          assignee_ids: capa.company_users.pluck(:id).join(",")
        },
        assignees: assignees,
        total_assignees: capa.company_users.count,
        standard_display_name: capa.standard&.display_name
      }
    else
      error_message = capa.errors.full_messages.join(", ")
      notification_html = render_to_string(partial: "shared/notification", locals: { message: error_message, type: :error, animated: true }, formats: [ :html ])
      render json: { error: error_message, notification_html: notification_html }, status: :unprocessable_entity
    end
  end

  def regenerate_questionnaire
    capa = current_company ? capa_visible_scope(base: Capa.where(company_id: current_company.id)).find_by(id: params[:id]) : nil

    unless capa
      notification_html = render_to_string(partial: "shared/notification", locals: { message: "CAPA not found", type: :error, animated: true }, formats: [ :html ])
      render json: { error: "CAPA not found", notification_html: notification_html }, status: :not_found and return
    end
    unless can_manage_capa?(capa)
      notification_html = render_to_string(partial: "shared/notification", locals: { message: "You do not have permission to manage this questionnaire.", type: :error, animated: true }, formats: [ :html ])
      render json: { error: "You do not have permission to manage this questionnaire.", notification_html: notification_html }, status: :forbidden and return
    end

    begin
      # Check credits before generation
      unless CreditService.has_sufficient_credits?(current_company, "GENERATE_CAPA_QUESTIONNAIRE", company_user: current_company_user)
        credits_needed = CreditService.get_cost("GENERATE_CAPA_QUESTIONNAIRE")
        available = current_company_user&.assigned_credits.to_i
        error_message = I18n.t("insufficient_user_credits", needed: credits_needed, available: available)
        notification_html = render_to_string(partial: "shared/notification", locals: { message: error_message, type: :error, animated: true }, formats: [ :html ])
        render json: { error: error_message, notification_html: notification_html }, status: :unprocessable_entity and return
      end

      service = CapaQuestionnaireService.new(capa)
      questionnaire_data = service.generate

      # Update or create questionnaire
      if capa.questionnaire
        capa.questionnaire.update!(questionnaire_data)
      else
        capa.create_questionnaire(questionnaire_data)
      end

      # Deduct credits after successful generation
      CreditService.deduct_credits(current_company, "GENERATE_CAPA_QUESTIONNAIRE", company_user: current_company_user)

      # Log audit action
      AuditLogService.log_action(
        actor_user: current_user,
        company: current_company,
        action: "GENERATE_CAPA_QUESTIONNAIRE",
        entity_type: "capa",
        entity_id: capa.id,
        payload: { manual: false, credits_used: CreditService.get_cost("GENERATE_CAPA_QUESTIONNAIRE") }
      )

      # Reload to get updated associations
      capa.reload

      # Generate notification
      notification_html = render_to_string(partial: "shared/notification", locals: { message: "Questionnaire regenerated successfully", type: :success, animated: true }, formats: [ :html ])

      render json: {
        message: "Questionnaire regenerated successfully",
        questionnaire: questionnaire_data,
        notification_html: notification_html
      }, status: :ok
    rescue => e
      Rails.logger.error "Failed to regenerate questionnaire for CAPA #{capa.id}: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      error_message = "Failed to regenerate questionnaire: #{e.message}"
      notification_html = render_to_string(partial: "shared/notification", locals: { message: error_message, type: :error, animated: true }, formats: [ :html ])
      render json: { error: error_message, notification_html: notification_html }, status: :unprocessable_entity
    end
  end

  def generate_actions
    capa = current_company ? capa_visible_scope(base: Capa.where(company_id: current_company.id)).find_by(id: params[:id]) : nil

    unless capa
      notification_html = render_to_string(partial: "shared/notification", locals: { message: "CAPA not found", type: :error, animated: true }, formats: [ :html ])
      render json: { error: "CAPA not found", notification_html: notification_html }, status: :not_found and return
    end
    unless can_manage_capa?(capa)
      notification_html = render_to_string(partial: "shared/notification", locals: { message: "You do not have permission to generate actions for this CAPA.", type: :error, animated: true }, formats: [ :html ])
      render json: { error: "You do not have permission to generate actions for this CAPA.", notification_html: notification_html }, status: :forbidden and return
    end

    questionnaire = capa.questionnaire
    unless questionnaire
      error_message = I18n.t("capa_management_requirements.generate_actions.errors.missing_questionnaire", default: "Complete the questionnaire before generating actions.")
      notification_html = render_to_string(partial: "shared/notification", locals: { message: error_message, type: :error, animated: true }, formats: [ :html ])
      render json: { error: error_message, notification_html: notification_html }, status: :unprocessable_entity and return
    end

    unless questionnaire.root_cause.present?
      error_message = I18n.t("capa_management_requirements.generate_actions.errors.missing_root_cause", default: "Add a root cause before generating actions.")
      notification_html = render_to_string(partial: "shared/notification", locals: { message: error_message, type: :error, animated: true }, formats: [ :html ])
      render json: { error: error_message, notification_html: notification_html }, status: :unprocessable_entity and return
    end

    begin
      # Check credits before generation
      unless CreditService.has_sufficient_credits?(current_company, "GENERATE_CAPA_ACTIONS", company_user: current_company_user)
        credits_needed = CreditService.get_cost("GENERATE_CAPA_ACTIONS")
        available = current_company_user&.assigned_credits.to_i
        error_message = I18n.t("insufficient_user_credits", needed: credits_needed, available: available)
        notification_html = render_to_string(partial: "shared/notification", locals: { message: error_message, type: :error, animated: true }, formats: [ :html ])
        render json: { error: error_message, notification_html: notification_html }, status: :unprocessable_entity and return
      end

      service = CapaActionGenerationService.new(capa)
      actions_data = service.generate

      created_actions = []
      actions_data["actions"].each do |action_data|
        action = CapaAction.create!(
          capa: capa,
          title: action_data["title"],
          action_type: action_data["action_type"],
          notes: action_data["notes"],
          status: "started",
          due_date: capa.due_date,
          created_by_id: current_user.id
        )

        created_actions << action
      end

      # Deduct credits after successful generation
      CreditService.deduct_credits(current_company, "GENERATE_CAPA_ACTIONS", company_user: current_company_user)

      # Reload to get updated associations
      capa.reload

      # Log audit action
      AuditLogService.log_action(
        actor_user: current_user,
        company: current_company,
        action: "GENERATE_CAPA_ACTIONS",
        entity_type: "capa",
        entity_id: capa.id,
        payload: {
          actions_count: created_actions.length,
          action_ids: created_actions.map(&:id),
          credits_used: CreditService.get_cost("GENERATE_CAPA_ACTIONS")
        }
      )

      # Generate notification
      notification_html = render_to_string(partial: "shared/notification", locals: { message: "5 actions generated successfully", type: :success, animated: true }, formats: [ :html ])

      render json: {
        message: "5 actions generated successfully",
        actions_count: created_actions.length,
        notification_html: notification_html
      }, status: :ok
    rescue => e
      Rails.logger.error "Failed to generate actions for CAPA #{capa.id}: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      error_message = "Failed to generate actions: #{e.message}"
      notification_html = render_to_string(partial: "shared/notification", locals: { message: error_message, type: :error, animated: true }, formats: [ :html ])
      render json: { error: error_message, notification_html: notification_html }, status: :unprocessable_entity
    end
  end

  def start_questionnaire_generation
    capa = current_company ? capa_visible_scope(base: Capa.where(company_id: current_company.id)).find_by(id: params[:id]) : nil

    unless capa
      render json: { error: "CAPA not found" }, status: :not_found and return
    end
    unless can_manage_capa?(capa)
      render json: { error: "You do not have permission to manage this questionnaire." }, status: :forbidden and return
    end

    # Determine current question number based on existing questionnaire
    current_question = 1
    existing_questions = {}

    if capa.questionnaire
      # Check which questions are already filled
      (1..5).each do |num|
        question_field = "question_#{num}"
        answer_field = "answer_#{num}"
        if capa.questionnaire.send(question_field).present? && capa.questionnaire.send(answer_field).present?
          existing_questions[num] = {
            question: capa.questionnaire.send(question_field),
            answer: capa.questionnaire.send(answer_field)
          }
          current_question = num + 1 if num < 5
        else
          break
        end
      end
    end

    render json: {
      current_question: current_question,
      existing_questions: existing_questions,
      is_complete: current_question >= 5
    }, status: :ok
  end

  def generate_question_pair
    capa = current_company ? capa_visible_scope(base: Capa.where(company_id: current_company.id)).find_by(id: params[:id]) : nil

    unless capa
      render json: { error: "CAPA not found" }, status: :not_found and return
    end
    unless can_manage_capa?(capa)
      render json: { error: "You do not have permission to manage this questionnaire." }, status: :forbidden and return
    end

    question_number = params[:question_number].to_i

    unless (1..5).include?(question_number)
      render json: { error: "Invalid question number. Must be between 1 and 5." }, status: :unprocessable_entity and return
    end

    begin
      # Build existing questions hash from questionnaire if it exists
      existing_questions = {}
      if capa.questionnaire
        (1..(question_number - 1)).each do |num|
          question_field = "question_#{num}"
          answer_field = "answer_#{num}"
          if capa.questionnaire.send(question_field).present? && capa.questionnaire.send(answer_field).present?
            existing_questions[num] = {
              question: capa.questionnaire.send(question_field),
              answer: capa.questionnaire.send(answer_field)
            }
          end
        end
      end

      service = CapaQuestionnaireService.new(capa)
      pair_data = service.generate_single_pair(question_number, existing_questions)

      render json: {
        question: pair_data["question"],
        answer: pair_data["answer"],
        question_number: question_number
      }, status: :ok
    rescue => e
      Rails.logger.error "Failed to generate question pair for CAPA #{capa.id}: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end

  def accept_question_pair
    capa = current_company ? capa_visible_scope(base: Capa.where(company_id: current_company.id)).find_by(id: params[:id]) : nil

    unless capa
      render json: { error: "CAPA not found" }, status: :not_found and return
    end
    unless can_manage_capa?(capa)
      render json: { error: "You do not have permission to edit this questionnaire." }, status: :forbidden and return
    end

    question_number = params[:question_number].to_i
    question = params[:question]
    answer = params[:answer]

    unless (1..5).include?(question_number)
      render json: { error: "Invalid question number. Must be between 1 and 5." }, status: :unprocessable_entity and return
    end

    if question.blank? || answer.blank?
      render json: { error: "Question and answer are required." }, status: :unprocessable_entity and return
    end

    begin
      # Create or update questionnaire
      questionnaire = capa.questionnaire || capa.build_questionnaire

      question_field = "question_#{question_number}="
      answer_field = "answer_#{question_number}="

      questionnaire.send(question_field, question)
      questionnaire.send(answer_field, answer)
      # Clear downstream answers when regenerating a mid-sequence question so later questions must be regenerated
      if question_number < 5
        ((question_number + 1)..5).each do |num|
          questionnaire.send("question_#{num}=", nil)
          questionnaire.send("answer_#{num}=", nil)
        end
        questionnaire.root_cause = nil
      end
      
      # If this is question 5, regenerate root cause summary from updated answers
      if question_number == 5
        service = CapaQuestionnaireService.new(capa)
        questionnaire.root_cause = service.generate_root_cause_summary(questionnaire)
      end

      questionnaire.save!

      # Log audit action
      AuditLogService.log_action(
        actor_user: current_user,
        company: current_company,
        action: "GENERATE_CAPA_QUESTIONNAIRE",
        entity_type: "capa",
        entity_id: capa.id,
        payload: {
          manual: true,
          question_number: question_number,
          step: "accept_question_pair"
        }
      )

      # Determine next question number
      next_question = question_number < 5 ? question_number + 1 : nil
      is_complete = question_number == 5

      render json: {
        message: "Question #{question_number} accepted",
        next_question: next_question,
        is_complete: is_complete,
        root_cause: questionnaire.root_cause
      }, status: :ok
    rescue => e
      Rails.logger.error "Failed to accept question pair for CAPA #{capa.id}: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end

  def regenerate_question_pair
    capa = current_company ? Capa.where(company_id: current_company.id).find_by(id: params[:id]) : nil

    unless capa
      render json: { error: "CAPA not found" }, status: :not_found and return
    end

    question_number = params[:question_number].to_i

    unless (1..5).include?(question_number)
      render json: { error: "Invalid question number. Must be between 1 and 5." }, status: :unprocessable_entity and return
    end

    begin
      # Build existing questions hash from questionnaire if it exists
      existing_questions = {}
      if capa.questionnaire
        (1..(question_number - 1)).each do |num|
          question_field = "question_#{num}"
          answer_field = "answer_#{num}"
          if capa.questionnaire.send(question_field).present? && capa.questionnaire.send(answer_field).present?
            existing_questions[num] = {
              question: capa.questionnaire.send(question_field),
              answer: capa.questionnaire.send(answer_field)
            }
          end
        end
      end

      service = CapaQuestionnaireService.new(capa)
      pair_data = service.generate_single_pair(question_number, existing_questions)

      render json: {
        question: pair_data["question"],
        answer: pair_data["answer"],
        question_number: question_number
      }, status: :ok
    rescue => e
      Rails.logger.error "Failed to regenerate question pair for CAPA #{capa.id}: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end

  def regenerate_root_cause
    capa = current_company ? capa_visible_scope(base: Capa.where(company_id: current_company.id)).find_by(id: params[:id]) : nil
    questionnaire = capa&.questionnaire

    unless capa && questionnaire
      render json: { error: "Questionnaire not found" }, status: :not_found and return
    end
    unless can_manage_capa?(capa)
      render json: { error: "You do not have permission to manage root cause for this CAPA." }, status: :forbidden and return
    end

    unless questionnaire_complete?(questionnaire)
      render json: { error: "Root cause can only be generated after all 5 questions are completed." }, status: :unprocessable_entity and return
    end

    begin
      action_type = "REGENERATE_ROOT_CAUSE"
      cost = CreditService.get_cost(action_type)

      unless CreditService.has_sufficient_credits?(current_company, action_type, company_user: current_company_user)
        available = current_company_user&.assigned_credits.to_i
        error_message = I18n.t("insufficient_user_credits", needed: cost, available: available)
        notification_html = render_to_string(
          partial: "shared/notification",
          locals: { message: error_message, type: :error, animated: true },
          formats: [ :html ]
        )
        render json: { error: error_message, notification_html: notification_html }, status: :unprocessable_entity and return
      end

      service = CapaQuestionnaireService.new(capa)
      new_root_cause = service.generate_root_cause_summary(questionnaire)
      questionnaire.update!(root_cause: new_root_cause)

      unless CreditService.deduct_credits(current_company, action_type, company_user: current_company_user)
        error_message = I18n.t("insufficient_user_credits", needed: cost, available: current_company_user&.assigned_credits.to_i)
        notification_html = render_to_string(
          partial: "shared/notification",
          locals: { message: error_message, type: :error, animated: true },
          formats: [ :html ]
        )
        render json: { error: error_message, notification_html: notification_html }, status: :unprocessable_entity and return
      end

      # Log audit action
      AuditLogService.log_action(
        actor_user: current_user,
        company: current_company,
        action: "UPDATE_CAPA_QUESTIONNAIRE",
        entity_type: "capa",
        entity_id: capa.id,
        payload: { step: "regenerate_root_cause", credits_used: cost }
      )

      notification_html = render_to_string(
        partial: "shared/notification",
        locals: { message: "Root cause regenerated successfully!", type: :success, animated: true },
        formats: [ :html ]
      )

      render json: {
        root_cause: questionnaire.root_cause,
        notification_html: notification_html
      }, status: :ok
    rescue => e
      Rails.logger.error "Failed to regenerate root cause for CAPA #{capa&.id}: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end

  def create_questionnaire
    capa = current_company ? capa_visible_scope(base: Capa.where(company_id: current_company.id)).find_by(id: params[:id]) : nil

    unless capa
      notification_html = render_to_string(partial: "shared/notification", locals: { message: "CAPA not found", type: :error, animated: true }, formats: [ :html ])
      render json: { error: "CAPA not found", notification_html: notification_html }, status: :not_found and return
    end
    unless can_manage_capa?(capa)
      notification_html = render_to_string(partial: "shared/notification", locals: { message: "You do not have permission to manage questionnaires for this CAPA.", type: :error, animated: true }, formats: [ :html ])
      render json: { error: "You do not have permission to manage questionnaires for this CAPA.", notification_html: notification_html }, status: :forbidden and return
    end

    if capa.questionnaire
      notification_html = render_to_string(partial: "shared/notification", locals: { message: "Questionnaire already exists", type: :error, animated: true }, formats: [ :html ])
      render json: { error: "Questionnaire already exists", notification_html: notification_html }, status: :unprocessable_entity and return
    end

    begin
      # Create empty questionnaire
      questionnaire = capa.create_questionnaire(
        question_1: nil,
        question_2: nil,
        question_3: nil,
        question_4: nil,
        question_5: nil,
        answer_1: nil,
        answer_2: nil,
        answer_3: nil,
        answer_4: nil,
        answer_5: nil,
        root_cause: nil
      )

      # Log audit action
      AuditLogService.log_action(
        actor_user: current_user,
        company: current_company,
        action: "GENERATE_CAPA_QUESTIONNAIRE",
        entity_type: "capa",
        entity_id: capa.id,
        payload: { manual: true }
      )

      notification_html = render_to_string(partial: "shared/notification", locals: { message: "Questionnaire created successfully", type: :success, animated: true }, formats: [ :html ])

      # Return questionnaire data for frontend to render
      render json: {
        message: "Questionnaire created successfully",
        notification_html: notification_html,
        questionnaire_id: questionnaire.id,
        questionnaire: {
          question_1: questionnaire.question_1,
          question_2: questionnaire.question_2,
          question_3: questionnaire.question_3,
          question_4: questionnaire.question_4,
          question_5: questionnaire.question_5,
          answer_1: questionnaire.answer_1,
          answer_2: questionnaire.answer_2,
          answer_3: questionnaire.answer_3,
          answer_4: questionnaire.answer_4,
          answer_5: questionnaire.answer_5,
          root_cause: questionnaire.root_cause
        }
      }, status: :created
    rescue ActiveRecord::RecordInvalid => e
      error_message = e.record.errors.full_messages.join(", ")
      notification_html = render_to_string(partial: "shared/notification", locals: { message: error_message, type: :error, animated: true }, formats: [ :html ])
      render json: { error: error_message, notification_html: notification_html }, status: :unprocessable_entity
    rescue => e
      Rails.logger.error "Failed to create questionnaire for CAPA #{capa.id}: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      error_message = "Failed to create questionnaire: #{e.message}"
      notification_html = render_to_string(partial: "shared/notification", locals: { message: error_message, type: :error, animated: true }, formats: [ :html ])
      render json: { error: error_message, notification_html: notification_html }, status: :unprocessable_entity
    end
  end

  def update_questionnaire
    capa = current_company ? capa_visible_scope(base: Capa.where(company_id: current_company.id)).find_by(id: params[:id]) : nil

    unless capa
      notification_html = render_to_string(partial: "shared/notification", locals: { message: "CAPA not found", type: :error, animated: true }, formats: [ :html ])
      render json: { error: "CAPA not found", notification_html: notification_html }, status: :not_found and return
    end
    unless can_manage_capa?(capa)
      notification_html = render_to_string(partial: "shared/notification", locals: { message: "You do not have permission to edit this questionnaire.", type: :error, animated: true }, formats: [ :html ])
      render json: { error: "You do not have permission to edit this questionnaire.", notification_html: notification_html }, status: :forbidden and return
    end

    unless capa.questionnaire
      notification_html = render_to_string(partial: "shared/notification", locals: { message: "Questionnaire not found", type: :error, animated: true }, formats: [ :html ])
      render json: { error: "Questionnaire not found", notification_html: notification_html }, status: :not_found and return
    end

    begin
      questionnaire_params = params.require(:questionnaire).permit(
        :question_1, :question_2, :question_3, :question_4, :question_5,
        :answer_1, :answer_2, :answer_3, :answer_4, :answer_5,
        :root_cause
      )

      # Preserve root_cause if it's blank or not provided
      # Only update root_cause if it's explicitly provided with a non-blank value
      if questionnaire_params.key?("root_cause") && questionnaire_params["root_cause"].blank?
        questionnaire_params = questionnaire_params.except("root_cause")
      end

      capa.questionnaire.update!(questionnaire_params)

      # Reload to get all fields including preserved root_cause
      capa.questionnaire.reload

      # Log audit action
      AuditLogService.log_action(
        actor_user: current_user,
        company: current_company,
        action: "UPDATE_CAPA_QUESTIONNAIRE",
        entity_type: "capa",
        entity_id: capa.id,
        payload: { updated_fields: questionnaire_params.keys }
      )

      notification_html = render_to_string(partial: "shared/notification", locals: { message: "Questionnaire updated successfully", type: :success, animated: true }, formats: [ :html ])
      render json: {
        message: "Questionnaire updated successfully",
        notification_html: notification_html,
        questionnaire: {
          question_1: capa.questionnaire.question_1,
          question_2: capa.questionnaire.question_2,
          question_3: capa.questionnaire.question_3,
          question_4: capa.questionnaire.question_4,
          question_5: capa.questionnaire.question_5,
          answer_1: capa.questionnaire.answer_1,
          answer_2: capa.questionnaire.answer_2,
          answer_3: capa.questionnaire.answer_3,
          answer_4: capa.questionnaire.answer_4,
          answer_5: capa.questionnaire.answer_5,
          root_cause: capa.questionnaire.root_cause
        }
      }, status: :ok
    rescue ActiveRecord::RecordInvalid => e
      error_message = e.record.errors.full_messages.join(", ")
      notification_html = render_to_string(partial: "shared/notification", locals: { message: error_message, type: :error, animated: true }, formats: [ :html ])
      render json: { error: error_message, notification_html: notification_html }, status: :unprocessable_entity
    rescue => e
      Rails.logger.error "Failed to update questionnaire for CAPA #{capa.id}: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      error_message = "Failed to update questionnaire: #{e.message}"
      notification_html = render_to_string(partial: "shared/notification", locals: { message: error_message, type: :error, animated: true }, formats: [ :html ])
      render json: { error: error_message, notification_html: notification_html }, status: :unprocessable_entity
    end
  end

  def archive
    capa = current_company ? capa_visible_scope(base: Capa.where(company_id: current_company.id)).find_by(id: params[:id]) : nil

    unless capa
      notification_html = render_to_string(partial: "shared/notification", locals: { message: "CAPA not found", type: :error, animated: true }, formats: [ :html ])
      render json: { error: "CAPA not found", notification_html: notification_html }, status: :not_found and return
    end
    unless can_manage_capa?(capa)
      notification_html = render_to_string(partial: "shared/notification", locals: { message: "You do not have permission to archive this CAPA.", type: :error, animated: true }, formats: [ :html ])
      render json: { error: "You do not have permission to archive this CAPA.", notification_html: notification_html }, status: :forbidden and return
    end

    # Use update_column to skip callbacks (we'll log explicitly)
    capa.update_column(:archived, true)

    # Log audit action
    AuditLogService.log_action(
      actor_user: current_user,
      company: current_company,
      action: "ARCHIVE_CAPA",
      entity_type: "capa",
      entity_id: capa.id,
      payload: { title: capa.title }
    )

    success_message = I18n.t("capa_management_ui.notifications.archive_success")
    notification_html = render_to_string(partial: "shared/notification", locals: { message: success_message, type: :success, animated: true }, formats: [ :html ])
    render json: { message: success_message, id: capa.id, notification_html: notification_html }
  rescue => e
    notification_html = render_to_string(partial: "shared/notification", locals: { message: e.message, type: :error, animated: true }, formats: [ :html ])
    render json: { error: e.message, notification_html: notification_html }, status: :unprocessable_entity
  end

  def unarchive
    capa = current_company ? capa_visible_scope(base: Capa.where(company_id: current_company.id)).find_by(id: params[:id]) : nil

    unless capa
      notification_html = render_to_string(partial: "shared/notification", locals: { message: "CAPA not found", type: :error, animated: true }, formats: [ :html ])
      render json: { error: "CAPA not found", notification_html: notification_html }, status: :not_found and return
    end
    unless can_manage_capa?(capa)
      notification_html = render_to_string(partial: "shared/notification", locals: { message: "You do not have permission to unarchive this CAPA.", type: :error, animated: true }, formats: [ :html ])
      render json: { error: "You do not have permission to unarchive this CAPA.", notification_html: notification_html }, status: :forbidden and return
    end

    # Use update_column to skip callbacks (we'll log explicitly)
    capa.update_column(:archived, false)

    # Log audit action
    AuditLogService.log_action(
      actor_user: current_user,
      company: current_company,
      action: "UNARCHIVE_CAPA",
      entity_type: "capa",
      entity_id: capa.id,
      payload: { title: capa.title }
    )

    success_message = I18n.t("capa_management_ui.notifications.unarchive_success")
    notification_html = render_to_string(partial: "shared/notification", locals: { message: success_message, type: :success, animated: true }, formats: [ :html ])
    render json: { message: success_message, id: capa.id, notification_html: notification_html }
  rescue => e
    notification_html = render_to_string(partial: "shared/notification", locals: { message: e.message, type: :error, animated: true }, formats: [ :html ])
    render json: { error: e.message, notification_html: notification_html }, status: :unprocessable_entity
  end

  def create_capa_action
    capa = current_company ? capa_visible_scope(base: Capa.where(company_id: current_company.id)).find_by(id: params[:capa_id]) : nil

    unless capa
      render json: { error: "CAPA not found" }, status: :not_found and return
    end
    unless can_manage_capa?(capa)
      render json: { error: "You do not have permission to add corrective/preventive actions to this CAPA." }, status: :forbidden and return
    end

    # Get company user IDs before filtering params
    company_user_ids = params[:capa_action][:company_user_ids] if params[:capa_action][:company_user_ids].present?

    # Filter permitted params
    action_params = capa_action_params
    action_params[:capa_id] = capa.id
    action_params[:due_date] = nil if action_params[:due_date].blank?

    @capa_action = CapaAction.new(action_params)
    @capa_action.created_by_id = current_user.id

    if @capa_action.save
      # Create assignments for selected company users (only from current company)
      allowed_ids = allowed_company_user_ids_for_capa(company_user_ids)
      if allowed_ids.present?
        added_company_users = CompanyUser.where(id: allowed_ids).includes(:user)
        allowed_ids.each do |company_user_id|
          CapaActionAssignment.create(capa_action: @capa_action, company_user_id: company_user_id)
          cu = added_company_users.find { |c| c.id.to_s == company_user_id.to_s }
          user_name = cu&.user&.name || I18n.t("capa_management_activity.na")
          AuditLogService.log_action(
            actor_user: current_user,
            company: current_company,
            action: "ASSIGN_USER_TO_CAPA_ACTION",
            entity_type: "capa_action",
            entity_id: @capa_action.id,
            payload: {
              company_user_id: company_user_id,
              user_name: user_name,
              action_title: @capa_action.title
            }
          )
          NotificationService.notify_capa_action_assigned(recipient: cu.user, capa: capa, capa_action: @capa_action, actor: current_user) if cu&.user
        end
      end

      # Reload to get associations
      @capa_action.reload

      # Log audit action
      AuditLogService.log_action(
        actor_user: current_user,
        company: current_company,
        action: "CREATE_CAPA_ACTION",
        entity_type: "capa_action",
        entity_id: @capa_action.id,
        payload: {
          capa_id: capa.id,
          action_title: @capa_action.title,
          action_type: @capa_action.action_type,
          status: @capa_action.status
        }
      )

      # Generate action row HTML
      action_row_html = render_to_string(partial: "dashboard/capa_management/action_row",
        locals: { action: @capa_action, capa: capa }, formats: [ :html ])

      # Generate activity log HTML (only if user is allowed to see it)
      @can_view_activity_log = can_view_capa_activity_log?(capa)
      if @can_view_activity_log
        @activities = AuditLog.for_capa_with_actions(capa).includes(:actor_user).order(created_at: :desc, id: :desc)
        activity_log_html = render_to_string(partial: "dashboard/capa_management/activity_tab", formats: [ :html ])
      else
        activity_log_html = nil
      end

      notification_html = render_to_string(partial: "shared/notification", locals: { message: "Action created successfully!", type: :success, animated: true }, formats: [ :html ])
      render json: {
        message: "Action created successfully!",
        notification_html: notification_html,
        action_html: action_row_html,
        activity_log_html: activity_log_html,
        action: @capa_action.as_json(include: { company_users: { include: :user } })
      }, status: :created
    else
      error_message = @capa_action.errors.full_messages.join(", ")
      notification_html = render_to_string(partial: "shared/notification", locals: { message: error_message, type: :error, animated: true }, formats: [ :html ])
      render json: { error: error_message, notification_html: notification_html }, status: :unprocessable_entity
    end
  end

  def update_capa_action
    capa = current_company ? capa_visible_scope(base: Capa.where(company_id: current_company.id)).find_by(id: params[:capa_id]) : nil
    capa_action = capa ? capa.capa_actions.find_by(id: params[:id]) : nil

    unless capa_action
      notification_html = render_to_string(partial: "shared/notification", locals: { message: "CAPA Action not found", type: :error, animated: true }, formats: [ :html ])
      render json: { error: "CAPA Action not found", notification_html: notification_html }, status: :not_found and return
    end
    unless can_manage_capa?(capa)
      notification_html = render_to_string(partial: "shared/notification", locals: { message: "You do not have permission to edit this action.", type: :error, animated: true }, formats: [ :html ])
      render json: { error: "You do not have permission to edit this action.", notification_html: notification_html }, status: :forbidden and return
    end

    # Filter permitted params
    action_params = capa_action_params
    action_params[:due_date] = nil if action_params[:due_date].blank?

    to_add_ids = []
    to_remove_ids = []
    ActiveRecord::Base.transaction do
      capa_action.update!(action_params)

      # Sync assignments if provided (including empty array to clear all assignments)
      if params[:capa_action].key?(:company_user_ids)
        unless can_assign_to_capa_action?(capa_action)
          notification_html = render_to_string(partial: "shared/notification", locals: { message: "You do not have permission to assign people to this action.", type: :error, animated: true }, formats: [ :html ])
          render json: { error: "You do not have permission to assign people to this action.", notification_html: notification_html }, status: :forbidden and return
        end
        new_ids = Array(params[:capa_action][:company_user_ids]).reject(&:blank?).map(&:to_s)
        new_ids = allowed_company_user_ids_for_capa(new_ids).map(&:to_s).uniq
        current_ids = capa_action.capa_action_assignments.pluck(:company_user_id).map(&:to_s)
        to_add_ids = new_ids - current_ids
        to_remove_ids = current_ids - new_ids

        to_add_ids.each { |cid| CapaActionAssignment.create!(capa_action: capa_action, company_user_id: cid) }
        CapaActionAssignment.where(capa_action: capa_action, company_user_id: to_remove_ids).delete_all if to_remove_ids.any?
      end
    end

    if capa_action.errors.empty?
      # Reload to get updated associations
      capa_action.reload

      # Log audit for users assigned to this action
      if to_add_ids.any?
        CompanyUser.where(id: to_add_ids).includes(:user).find_each do |cu|
          user_name = cu.user&.name || I18n.t("capa_management_activity.na")
          AuditLogService.log_action(
            actor_user: current_user,
            company: current_company,
            action: "ASSIGN_USER_TO_CAPA_ACTION",
            entity_type: "capa_action",
            entity_id: capa_action.id,
            payload: {
              company_user_id: cu.id,
              user_name: user_name,
              action_title: capa_action.title
            }
          )
          NotificationService.notify_capa_action_assigned(recipient: cu.user, capa: capa, capa_action: capa_action, actor: current_user) if cu.user
        end
      end
      if to_remove_ids.any?
        CompanyUser.where(id: to_remove_ids).includes(:user).find_each do |cu|
          user_name = cu.user&.name || I18n.t("capa_management_activity.na")
          AuditLogService.log_action(
            actor_user: current_user,
            company: current_company,
            action: "UNASSIGN_USER_FROM_CAPA_ACTION",
            entity_type: "capa_action",
            entity_id: capa_action.id,
            payload: {
              company_user_id: cu.id,
              user_name: user_name,
              action_title: capa_action.title
            }
          )
          NotificationService.notify_capa_action_unassigned(recipient: cu.user, capa: capa, capa_action: capa_action, actor: current_user) if cu.user
        end
      end

      # Log audit action
      AuditLogService.log_action(
        actor_user: current_user,
        company: current_company,
        action: "UPDATE_CAPA_ACTION",
        entity_type: "capa_action",
        entity_id: capa_action.id,
        payload: {
          capa_id: capa.id,
          action_title: capa_action.title,
          action_type: capa_action.action_type,
          changes: action_params
        }
      )

      # Generate updated action row HTML
      action_row_html = render_to_string(partial: "dashboard/capa_management/action_row",
        locals: { action: capa_action, capa: capa }, formats: [ :html ])

      # Generate activity log HTML (only if user is allowed to see it)
      @can_view_activity_log = can_view_capa_activity_log?(capa)
      if @can_view_activity_log
        @activities = AuditLog.for_capa_with_actions(capa).includes(:actor_user).order(created_at: :desc, id: :desc)
        activity_log_html = render_to_string(partial: "dashboard/capa_management/activity_tab", formats: [ :html ])
      else
        activity_log_html = nil
      end

      notification_html = render_to_string(partial: "shared/notification", locals: { message: "Action updated successfully!", type: :success, animated: true }, formats: [ :html ])
      render json: {
        message: "Action updated successfully!",
        notification_html: notification_html,
        action_html: action_row_html,
        activity_log_html: activity_log_html,
        action: capa_action.as_json(include: { company_users: { include: :user } })
      }, status: :ok
    else
      error_message = capa_action.errors.full_messages.join(", ")
      notification_html = render_to_string(partial: "shared/notification", locals: { message: error_message, type: :error, animated: true }, formats: [ :html ])
      render json: { error: error_message, notification_html: notification_html }, status: :unprocessable_entity
    end
  end

  def destroy_capa_action
    capa = current_company ? capa_visible_scope(base: Capa.where(company_id: current_company.id)).find_by(id: params[:capa_id]) : nil
    capa_action = capa ? capa.capa_actions.find_by(id: params[:id]) : nil

    unless capa_action
      notification_html = render_to_string(partial: "shared/notification", locals: { message: "CAPA Action not found", type: :error, animated: true }, formats: [ :html ])
      render json: { error: "CAPA Action not found", notification_html: notification_html }, status: :not_found and return
    end
    unless can_manage_capa?(capa)
      notification_html = render_to_string(partial: "shared/notification", locals: { message: "You do not have permission to delete this action.", type: :error, animated: true }, formats: [ :html ])
      render json: { error: "You do not have permission to delete this action.", notification_html: notification_html }, status: :forbidden and return
    end

    # Save action details before destroying
    action_title = capa_action.title
    action_type = capa_action.action_type
    action_id = capa_action.id

    capa_action.destroy

    # Log audit action
    AuditLogService.log_action(
      actor_user: current_user,
      company: current_company,
      action: "DELETE_CAPA_ACTION",
      entity_type: "capa_action",
      entity_id: action_id,
      payload: {
        capa_id: capa.id,
        action_title: action_title,
        action_type: action_type
      }
    )

    # Generate activity log HTML (only if user is allowed to see it)
    @can_view_activity_log = can_view_capa_activity_log?(capa)
    if @can_view_activity_log
      @activities = AuditLog.for_capa_with_actions(capa).includes(:actor_user).order(created_at: :desc, id: :desc)
      activity_log_html = render_to_string(partial: "dashboard/capa_management/activity_tab", formats: [ :html ])
    else
      activity_log_html = nil
    end

    notification_html = render_to_string(partial: "shared/notification", locals: { message: "Action deleted successfully!", type: :success, animated: true }, formats: [ :html ])
    render json: { message: "Action deleted successfully!", notification_html: notification_html, activity_log_html: activity_log_html }, status: :ok
  end

  def suggest_clauses
    capa = current_company ? capa_visible_scope(base: Capa.where(company_id: current_company.id)).find_by(id: params[:id]) : nil

    unless capa
      notification_html = render_to_string(partial: "shared/notification", locals: { message: "CAPA not found", type: :error, animated: true }, formats: [ :html ])
      render json: { error: "CAPA not found", notification_html: notification_html }, status: :not_found and return
    end
    # No extra permission check: suggest_clauses only returns clause suggestions; anyone who can see the CAPA can use it.

    begin
      # Check credits before generation
      unless CreditService.has_sufficient_credits?(current_company, "SUGGEST_CAPA_CLAUSES", company_user: current_company_user)
        credits_needed = CreditService.get_cost("SUGGEST_CAPA_CLAUSES")
        available = current_company_user&.assigned_credits.to_i
        error_message = I18n.t("insufficient_user_credits", needed: credits_needed, available: available)
        notification_html = render_to_string(partial: "shared/notification", locals: { message: error_message, type: :error, animated: true }, formats: [ :html ])
        render json: { error: error_message, notification_html: notification_html }, status: :unprocessable_entity and return
      end

      service = CapaClauseSuggestionService.new(capa, current_company)
      suggestions_data = service.suggest

      # Map suggested clause codes to actual clauses
      suggested_clause_codes = suggestions_data["suggestions"].map { |s| s["clause_code"] }

      # Find clauses matching the suggested codes that are available to the company
      # Exclude already linked clauses
      linked_clause_ids = capa.clauses.pluck(:id)

      suggested_clauses = Clause.joins(standard_version: { standard: :company_standards })
                                .where(company_standards: { company_id: current_company.id })
                                .where(code: suggested_clause_codes)
                                .where.not(id: linked_clause_ids)
                                .includes(:standard_version, :clause_translations, :parent, standard_version: :standard)
                                .distinct

      # Format results to match search API format
      formatted_results = suggested_clauses.map do |clause|
        standard = clause.standard_version&.standard
        suggestion = suggestions_data["suggestions"].find { |s| s["clause_code"] == clause.code }

        {
          id: clause.id,
          type: clause.parent.present? ? "Sub-Clause" : "Clause",
          code: clause.code,
          title: clause.title("en"),
          standard_name: standard&.display_name("en") || standard&.code,
          is_sub_clause: clause.parent.present?,
          reasoning: suggestion&.dig("reasoning") || "Relevant to this CAPA"
        }
      end

      # Deduct credits after successful generation
      CreditService.deduct_credits(current_company, "SUGGEST_CAPA_CLAUSES", company_user: current_company_user)

      # Log audit action
      AuditLogService.log_action(
        actor_user: current_user,
        company: current_company,
        action: "SUGGEST_CAPA_CLAUSES",
        entity_type: "capa",
        entity_id: capa.id,
        payload: {
          suggestions_count: formatted_results.length,
          summary: suggestions_data["summary"],
          credits_used: CreditService.get_cost("SUGGEST_CAPA_CLAUSES")
        }
      )

      # Generate notification
      notification_html = render_to_string(partial: "shared/notification", locals: { message: "#{formatted_results.length} clause(s) suggested", type: :success, animated: true }, formats: [ :html ])

      render json: {
        results: formatted_results,
        summary: suggestions_data["summary"],
        notification_html: notification_html
      }, status: :ok
    rescue => e
      Rails.logger.error "Failed to suggest clauses for CAPA #{capa.id}: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      error_message = "Failed to suggest clauses: #{e.message}"
      notification_html = render_to_string(partial: "shared/notification", locals: { message: error_message, type: :error, animated: true }, formats: [ :html ])
      render json: { error: error_message, notification_html: notification_html }, status: :unprocessable_entity
    end
  end

  def link_clauses
    @capa = if current_company
      capa_visible_scope(base: Capa.where(company_id: current_company.id)).find_by(id: params[:capa_id])
    else
      nil
    end

    unless @capa
      render json: { success: false, message: "CAPA not found" }, status: :not_found and return
    end
    unless can_link_documents_to_capa?(@capa)
      render json: { success: false, message: "You do not have permission to link clauses to this CAPA." }, status: :forbidden and return
    end

    items = params[:items] || []
    created_count = 0
    errors = []
    linked_clauses = []

    items.each do |item_params|
      clause_id = item_params[:id]

      unless clause_id.present?
        errors << "Clause ID is required"
        next
      end

      # Only allow clauses from standards assigned to current company
      clause = Clause.joins(standard_version: { standard: :company_standards })
                     .where(company_standards: { company_id: current_company.id, status: "active" })
                     .includes(:parent)
                     .find_by(id: clause_id)
      unless clause
        errors << "Clause #{clause_id} not found or not available for your company"
        next
      end

      # Check if already linked - skip if already linked
      existing = CapaClause.find_by(capa_id: @capa.id, clause_id: clause_id)
      if existing
        next  # Skip clauses that are already linked
      end

      # Create the capa_clause
      capa_clause = CapaClause.new(capa: @capa, clause_id: clause_id)

      if capa_clause.save
        created_count += 1
        linked_clauses << clause
      else
        errors << capa_clause.errors.full_messages.join(", ")
      end
    end

    # Log activities for successfully linked clauses
    linked_clauses.each do |clause|
      AuditLogService.log_action(
        actor_user: current_user,
        company: current_company,
        action: "LINK_CLAUSE_TO_CAPA",
        entity_type: "clause",
        entity_id: clause.id,
        payload: {
          capa_id: @capa.id,
          clause_code: clause.code,
          clause_title: clause.title("en")
        }
      )
    end

    respond_to do |format|
      if created_count > 0 && errors.empty?
        format.json { render json: {
          success: true,
          message: "#{created_count} clause(s) linked successfully",
          created_count: created_count
        }, status: :created }
      elsif created_count > 0
        format.json { render json: {
          success: true,
          message: "#{created_count} clause(s) linked successfully. Some errors occurred.",
          created_count: created_count,
          errors: errors
        }, status: :ok }
      elsif created_count == 0 && errors.empty?
        format.json { render json: {
          success: true,
          message: "No clauses linked",
          created_count: created_count,
          errors: errors
        }, status: :ok }
      else
        format.json { render json: {
          success: false,
          message: "Failed to link clauses",
          errors: errors
        }, status: :unprocessable_entity }
      end
    end
  end

  def link_documents
    @capa = if current_company
      capa_visible_scope(base: Capa.where(company_id: current_company.id)).find_by(id: params[:capa_id])
    else
      nil
    end

    unless @capa
      notification_html = render_to_string(partial: "shared/notification", locals: { message: "CAPA not found", type: :error, animated: true }, formats: [ :html ])
      render json: { success: false, message: "CAPA not found", notification_html: notification_html }, status: :not_found and return
    end
    

    
    unless can_link_documents_to_capa?(@capa)
      notification_html = render_to_string(partial: "shared/notification", locals: { message: "You do not have permission to link documents to this CAPA.", type: :error, animated: true }, formats: [ :html ])
      render json: { success: false, message: "You do not have permission to link documents to this CAPA.", notification_html: notification_html }, status: :forbidden and return
    end

    upload_ids = params[:upload_ids] || []
    created_count = 0
    errors = []
    linked_documents = []

    upload_ids.each do |upload_id|
      unless upload_id.present?
        errors << "Upload ID is required"
        next
      end

      # Only allow uploads that belong to current company and are visible to current user
      upload = Upload.find_by(id: upload_id)
      unless upload && upload.visible_to_user?(current_user) && upload.company_id == current_company&.id
        errors << "Document #{upload_id} not found or not available"
        next
      end

      # Check if already linked - skip if already linked
      existing = EvidenceAttachment.find_by(attachable_type: "Capa", attachable_id: @capa.id, upload_id: upload_id)
      if existing
        next  # Skip documents that are already linked
      end

      # Create the evidence_attachment
      evidence_attachment = EvidenceAttachment.new(attachable: @capa, upload: upload, attached_by: current_company_user&.user&.id)

      if evidence_attachment.save
        created_count += 1
        linked_documents << upload
      else
        errors << evidence_attachment.errors.full_messages.join(", ")
      end
    end

    # Log audit actions for successfully linked documents
    linked_documents.each do |upload|
      AuditLogService.log_action(
        actor_user: current_user,
        company: current_company,
        action: "LINK_DOCUMENT_TO_CAPA",
        entity_type: "capa",
        entity_id: @capa.id,
        payload: {
          upload_id: upload.id,
          filename: upload.filename || upload.name,
          display_name: upload.display_name
        }
      )
    end

    # Notify all users assigned to the CAPA (except the actor) and notify auditors
    if linked_documents.any?
      doc_name = linked_documents.one? ? (linked_documents.first.display_name.presence || linked_documents.first.filename) : nil
      NotificationService.notify_capa_evidence_attached(
        capa: @capa,
        actor: current_user,
        document_name: doc_name,
        document_count: linked_documents.size > 1 ? linked_documents.size : nil
      )
      NotificationService.notify_auditors_capa_evidence_attached(capa: @capa, actor: current_user, document_name: doc_name, document_count: linked_documents.size > 1 ? linked_documents.size : nil)
    end

    respond_to do |format|
      if created_count > 0 && errors.empty?
        # Generate notification HTML
        notification_html = render_to_string(
          partial: "shared/notification",
          locals: { message: "#{created_count} document(s) linked successfully", type: :success, animated: true },
          formats: [ :html ]
        )

        # Format documents for response
        documents = linked_documents.map do |upload|
          {
            id: upload.id,
            name: upload.name,
            filename: upload.filename,
            display_name: upload.display_name,
            mime_type: upload.mime_type,
            notes: upload.notes,
            created_at: upload.created_at.strftime("%b %d, %Y"),
            file_url: helpers.signed_file_url(upload.file, disposition: "attachment")
          }
        end

        format.json { render json: {
          success: true,
          message: "#{created_count} document(s) linked successfully",
          notification_html: notification_html,
          created_count: created_count,
          documents: documents
        }, status: :created }
      elsif created_count > 0
        notification_html = render_to_string(
          partial: "shared/notification",
          locals: { message: "#{created_count} document(s) linked successfully. Some errors occurred.", type: :success, animated: true },
          formats: [ :html ]
        )
        format.json { render json: {
          success: true,
          message: "#{created_count} document(s) linked successfully. Some errors occurred.",
          notification_html: notification_html,
          created_count: created_count,
          errors: errors
        }, status: :ok }
      elsif created_count == 0 && errors.empty?
        notification_html = render_to_string(
          partial: "shared/notification",
          locals: { message: "No documents linked. They may already be linked.", type: :info, animated: true },
          formats: [ :html ]
        )
        format.json { render json: {
          success: true,
          message: "No documents linked",
          notification_html: notification_html,
          created_count: created_count,
          errors: errors
        }, status: :ok }
      else
        notification_html = render_to_string(
          partial: "shared/notification",
          locals: { message: "Failed to link documents: #{errors.join(', ')}", type: :error, animated: true },
          formats: [ :html ]
        )
        format.json { render json: {
          success: false,
          message: "Failed to link documents",
          notification_html: notification_html,
          errors: errors
        }, status: :unprocessable_entity }
      end
    end
  end

  def unlink_clause
    @capa = if current_company
      capa_visible_scope(base: Capa.where(company_id: current_company.id)).find_by(id: params[:capa_id])
    else
      nil
    end

    unless @capa
      render json: { success: false, message: "CAPA not found" }, status: :not_found and return
    end
    unless can_link_documents_to_capa?(@capa)
      render json: { success: false, message: "You do not have permission to unlink clauses from this CAPA." }, status: :forbidden and return
    end

    clause_id = params[:clause_id]

    unless clause_id.present?
      render json: { success: false, message: "Clause ID is required" }, status: :unprocessable_entity and return
    end

    capa_clause = CapaClause.includes(clause: :parent).find_by(capa_id: @capa.id, clause_id: clause_id)

    unless capa_clause
      render json: { success: false, message: "Clause is not linked to this CAPA" }, status: :not_found and return
    end

    # Get clause before destroying the join record
    clause = capa_clause.clause

    if capa_clause.destroy
      # Log audit action
      AuditLogService.log_action(
        actor_user: current_user,
        company: current_company,
        action: "UNLINK_CLAUSE_FROM_CAPA",
        entity_type: "clause",
        entity_id: clause.id,
        payload: {
          capa_id: @capa.id,
          clause_code: clause.code,
          clause_title: clause.title("en")
        }
      )

      render json: { success: true, message: "Clause unlinked successfully" }, status: :ok
    else
      render json: { success: false, message: "Failed to unlink clause" }, status: :unprocessable_entity
    end
  end

  def unlink_document
    @capa = if current_company
      capa_visible_scope(base: Capa.where(company_id: current_company.id)).find_by(id: params[:capa_id])
    else
      nil
    end

    unless @capa
      render json: { success: false, message: "CAPA not found" }, status: :not_found and return
    end
    unless can_link_documents_to_capa?(@capa)
      render json: { success: false, message: "You do not have permission to unlink documents from this CAPA." }, status: :forbidden and return
    end

    upload_id = params[:upload_id]

    unless upload_id.present?
      render json: { success: false, message: "Upload ID is required" }, status: :unprocessable_entity and return
    end

    evidence_attachment = EvidenceAttachment.includes(:upload).find_by(attachable_type: "Capa", attachable_id: @capa.id, upload_id: upload_id)

    unless evidence_attachment
      render json: { success: false, message: "Document is not linked to this CAPA" }, status: :not_found and return
    end

    # Get upload before destroying the join record
    upload = evidence_attachment.upload

    if evidence_attachment.destroy
      # Log audit action
      AuditLogService.log_action(
        actor_user: current_user,
        company: current_company,
        action: "UNLINK_DOCUMENT_FROM_CAPA",
        entity_type: "capa",
        entity_id: @capa.id,
        payload: {
          upload_id: upload.id,
          filename: upload.filename || upload.name,
          display_name: upload.display_name
        }
      )

      render json: { success: true, message: "Document unlinked successfully" }, status: :ok
    else
      render json: { success: false, message: "Failed to unlink document" }, status: :unprocessable_entity
    end
  end

  # --- CAPA Action dedicated page (show, evidence, comments) ---

  def show_capa_action
    @capa = capa_visible_scope(base: Capa.where(company_id: current_company&.id)).find_by(id: params[:capa_id])
    unless @capa
      redirect_to dashboard_capa_management_list_path, alert: "CAPA not found"
      return
    end
    @capa_action = @capa.capa_actions.includes(:capa, evidence_attachments: [ :upload, :attached_by_user ], company_users: :user).find_by(id: params[:id])
    unless @capa_action
      redirect_to dashboard_capa_management_show_path(@capa), alert: "Action not found"
      return
    end
    # Contributors may only open actions they are assigned to.
    # Auditors may open any action on a CAPA they are assigned to or created.
    cu = current_user&.company_user
    if cu && cu.company_contributor? && !assignee_of_capa_action?(@capa_action)
      redirect_to dashboard_capa_management_show_path(@capa), alert: "You do not have access to this action."
      return
    end
    if cu && cu.company_auditor?
      auditor_has_capa_access = @capa.created_by_id == current_user.id ||
                                @capa.capa_assignments.exists?(company_user_id: cu.id)
      unless auditor_has_capa_access || assignee_of_capa_action?(@capa_action)
        redirect_to dashboard_capa_management_show_path(@capa), alert: "You do not have access to this action."
        return
      end
    end
    @comments = @capa_action.comments.root_only.includes(user: [ :profile_image_attachment ], replies: { user: [ :profile_image_attachment ] }).order(created_at: :asc)
    @folders_for_upload = @capa.company_id.present? ? Folder.where(company_id: @capa.company_id).where.not(company_id: nil).order(:name) : Folder.none
    @company_users = current_company ? current_company.company_users.includes(:user) : CompanyUser.none
  end

  def link_capa_action_documents
    @capa = capa_visible_scope(base: Capa.where(company_id: current_company&.id)).find_by(id: params[:capa_id])
    unless @capa
      render json: { success: false, message: "CAPA not found" }, status: :not_found and return
    end
    @capa_action = @capa.capa_actions.find_by(id: params[:id])
    unless @capa_action
      render json: { success: false, message: "Action not found" }, status: :not_found and return
    end
    unless can_link_documents_to_capa_action?(@capa_action)
      render json: { success: false, message: "You do not have permission to link documents to this action." }, status: :forbidden and return
    end

    upload_ids = params[:upload_ids] || []
    created_count = 0
    errors = []
    linked_documents = []

    upload_ids.each do |upload_id|
      next unless upload_id.present?
      upload = Upload.find_by(id: upload_id)
      unless upload && upload.visible_to_user?(current_user) && upload.company_id == current_company&.id
        errors << "Document #{upload_id} not found or not available"
        next
      end
      existing = EvidenceAttachment.find_by(attachable_type: "CapaAction", attachable_id: @capa_action.id, upload_id: upload_id)
      next if existing

      evidence_attachment = EvidenceAttachment.new(attachable: @capa_action, upload: upload, attached_by: current_company_user&.user&.id)
      if evidence_attachment.save
        created_count += 1
        linked_documents << upload
      else
        errors << evidence_attachment.errors.full_messages.join(", ")
      end
    end

    linked_documents.each do |upload|
      AuditLogService.log_action(
        actor_user: current_user,
        company: current_company,
        action: "LINK_DOCUMENT_TO_CAPA_ACTION",
        entity_type: "CapaAction",
        entity_id: @capa_action.id,
        payload: { upload_id: upload.id, filename: upload.filename || upload.name, display_name: upload.display_name }
      )
    end

    if linked_documents.any?
      doc_name = linked_documents.one? ? (linked_documents.first.display_name.presence || linked_documents.first.filename) : nil
      NotificationService.notify_capa_evidence_attached(capa: @capa, actor: current_user, document_name: doc_name, document_count: linked_documents.size > 1 ? linked_documents.size : nil)
      NotificationService.notify_auditors_capa_evidence_attached(capa: @capa, capa_action: @capa_action, actor: current_user, document_name: doc_name, document_count: linked_documents.size > 1 ? linked_documents.size : nil)
    end

    respond_to do |format|
      if created_count > 0 && errors.empty?
        notification_html = render_to_string(partial: "shared/notification", locals: { message: "#{created_count} document(s) linked successfully", type: :success, animated: true }, formats: [ :html ])
        format.json { render json: { success: true, message: "#{created_count} document(s) linked successfully", notification_html: notification_html, created_count: created_count }, status: :created }
      elsif created_count > 0
        notification_html = render_to_string(partial: "shared/notification", locals: { message: "#{created_count} document(s) linked. Some errors occurred.", type: :success, animated: true }, formats: [ :html ])
        format.json { render json: { success: true, notification_html: notification_html, created_count: created_count, errors: errors }, status: :ok }
      elsif created_count == 0 && errors.empty?
        notification_html = render_to_string(partial: "shared/notification", locals: { message: "No documents linked. They may already be linked.", type: :info, animated: true }, formats: [ :html ])
        format.json { render json: { success: true, notification_html: notification_html }, status: :ok }
      else
        notification_html = render_to_string(partial: "shared/notification", locals: { message: "Failed to link documents: #{errors.join(', ')}", type: :error, animated: true }, formats: [ :html ])
        format.json { render json: { success: false, message: "Failed to link documents", notification_html: notification_html, errors: errors }, status: :unprocessable_entity }
      end
    end
  end

  def unlink_capa_action_document
    @capa = capa_visible_scope(base: Capa.where(company_id: current_company&.id)).find_by(id: params[:capa_id])
    unless @capa
      render json: { success: false, message: "CAPA not found" }, status: :not_found and return
    end
    @capa_action = @capa.capa_actions.find_by(id: params[:id])
    unless @capa_action
      render json: { success: false, message: "Action not found" }, status: :not_found and return
    end
    unless can_link_documents_to_capa_action?(@capa_action)
      render json: { success: false, message: "You do not have permission to unlink documents from this action." }, status: :forbidden and return
    end

    upload_id = params[:upload_id]
    unless upload_id.present?
      render json: { success: false, message: "Upload ID is required" }, status: :unprocessable_entity and return
    end

    evidence_attachment = EvidenceAttachment.find_by(attachable_type: "CapaAction", attachable_id: @capa_action.id, upload_id: upload_id)
    unless evidence_attachment
      render json: { success: false, message: "Document is not linked to this action" }, status: :not_found and return
    end
    upload = evidence_attachment.upload
    if evidence_attachment.destroy
      AuditLogService.log_action(
        actor_user: current_user,
        company: current_company,
        action: "UNLINK_DOCUMENT_FROM_CAPA_ACTION",
        entity_type: "CapaAction",
        entity_id: @capa_action.id,
        payload: { upload_id: upload.id, filename: upload.filename || upload.name, display_name: upload.display_name }
      )
      render json: { success: true, message: "Document unlinked successfully" }, status: :ok
    else
      render json: { success: false, message: "Failed to unlink document" }, status: :unprocessable_entity
    end
  end

  def create_capa_action_comment
    @capa = capa_visible_scope(base: Capa.where(company_id: current_company&.id)).find_by(id: params[:capa_id])
    unless @capa
      render json: { success: false, message: "CAPA not found" }, status: :not_found and return
    end
    @capa_action = @capa.capa_actions.find_by(id: params[:id])
    unless @capa_action
      render json: { success: false, message: "Action not found" }, status: :not_found and return
    end

    body = params[:comment]&.dig(:body)&.to_s&.strip
    unless body.present?
      render json: { success: false, message: "Comment body is required" }, status: :unprocessable_entity and return
    end

    parent_id = params[:comment]&.dig(:parent_id)&.presence
    parent = nil
    if parent_id.present?
      parent = @capa_action.comments.find_by(id: parent_id)
      unless parent
        render json: { success: false, message: "Parent comment not found" }, status: :unprocessable_entity and return
      end
    end

    comment = @capa_action.comments.build(body: body, user: current_user, parent: parent)
    if comment.save
      comment_json = {
        id: comment.id,
        body: comment.body,
        user_name: comment.user.name,
        user_id: comment.user_id,
        parent_id: comment.parent_id,
        created_at: comment.created_at.iso8601,
        replies: []
      }
      notification_html = render_to_string(partial: "shared/notification", locals: { message: I18n.t("capa_action_show.comment_added"), type: :success, animated: true }, formats: [ :html ])
      if parent.nil?
        comment_html = render_to_string(partial: "capa_action_comment", locals: { comment: comment, capa: @capa, capa_action: @capa_action }, formats: [ :html ])
        render json: { success: true, comment: comment_json, comment_html: comment_html, notification_html: notification_html }, status: :created
      else
        reply_html = render_to_string(partial: "capa_action_comment_reply", locals: { reply: comment, can_delete: can_delete_capa_action_comment?(@capa), parent_comment_id: parent.id }, formats: [ :html ])
        render json: { success: true, comment: comment_json, parent_id: parent.id, reply_html: reply_html, notification_html: notification_html }, status: :created
      end
    else
      render json: { success: false, message: comment.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end

  def destroy_capa_action_comment
    @capa = capa_visible_scope(base: Capa.where(company_id: current_company&.id)).find_by(id: params[:capa_id])
    unless @capa
      render json: { success: false, message: "CAPA not found" }, status: :not_found and return
    end
    @capa_action = @capa.capa_actions.find_by(id: params[:id])
    unless @capa_action
      render json: { success: false, message: "Action not found" }, status: :not_found and return
    end
    comment = @capa_action.comments.find_by(id: params[:comment_id])
    unless comment
      render json: { success: false, message: "Comment not found" }, status: :not_found and return
    end
    unless can_delete_capa_action_comment?(@capa)
      render json: { success: false, message: "Not allowed to delete comments" }, status: :forbidden and return
    end
    comment.destroy
    notification_html = render_to_string(partial: "shared/notification", locals: { message: I18n.t("capa_action_show.comment_deleted"), type: :success, animated: true }, formats: [ :html ])
    render json: { success: true, comment_id: comment.id, parent_id: comment.parent_id, notification_html: notification_html }
  end

  def bulk_archive
    unless current_company
      error_message = I18n.t("capa_management_ui.notifications.no_company_context")
      notification_html = render_to_string(partial: "shared/notification", locals: { message: error_message, type: :error, animated: true }, formats: [ :html ])
      render json: { error: error_message, notification_html: notification_html }, status: :unprocessable_entity and return
    end

    capa_ids = params[:capa_ids] || []
    if capa_ids.empty?
      error_message = I18n.t("capa_management_ui.notifications.no_capas_selected")
      notification_html = render_to_string(partial: "shared/notification", locals: { message: error_message, type: :error, animated: true }, formats: [ :html ])
      render json: { error: error_message, notification_html: notification_html }, status: :unprocessable_entity and return
    end

    capas = capa_visible_scope(base: Capa.where(company_id: current_company.id)).where(id: capa_ids)
    archived_count = 0
    errors = []

    capas.each do |capa|
      next unless can_manage_capa?(capa)
      begin
        capa.update_column(:archived, true)
        AuditLogService.log_action(
          actor_user: current_user,
          company: current_company,
          action: "ARCHIVE_CAPA",
          entity_type: "capa",
          entity_id: capa.id,
          payload: { title: capa.title, bulk: true }
        )
        archived_count += 1
      rescue => e
        errors << I18n.t("capa_management_ui.notifications.archive_failed", id: capa.id, error: e.message)
      end
    end

    if archived_count > 0 && errors.empty?
      message = I18n.t("capa_management_ui.notifications.bulk_archive_success", count: archived_count)
      notification_html = render_to_string(partial: "shared/notification", locals: { message: message, type: :success, animated: true }, formats: [ :html ])
      render json: { message: message, notification_html: notification_html, archived_count: archived_count }
    elsif archived_count > 0
      message = I18n.t("capa_management_ui.notifications.bulk_archive_partial", count: archived_count, errors: errors.join(', '))
      notification_html = render_to_string(partial: "shared/notification", locals: { message: message, type: :success, animated: true }, formats: [ :html ])
      render json: { message: message, notification_html: notification_html, archived_count: archived_count, errors: errors }
    else
      error_message = I18n.t("capa_management_ui.notifications.bulk_archive_error", errors: errors.join(', '))
      notification_html = render_to_string(partial: "shared/notification", locals: { message: error_message, type: :error, animated: true }, formats: [ :html ])
      render json: { error: error_message, notification_html: notification_html }, status: :unprocessable_entity
    end
  end

  def bulk_unarchive
    unless current_company
      error_message = I18n.t("capa_management_ui.notifications.no_company_context")
      notification_html = render_to_string(partial: "shared/notification", locals: { message: error_message, type: :error, animated: true }, formats: [ :html ])
      render json: { error: error_message, notification_html: notification_html }, status: :unprocessable_entity and return
    end

    capa_ids = params[:capa_ids] || []
    if capa_ids.empty?
      error_message = I18n.t("capa_management_ui.notifications.no_capas_selected")
      notification_html = render_to_string(partial: "shared/notification", locals: { message: error_message, type: :error, animated: true }, formats: [ :html ])
      render json: { error: error_message, notification_html: notification_html }, status: :unprocessable_entity and return
    end

    capas = capa_visible_scope(base: Capa.where(company_id: current_company.id)).where(id: capa_ids)
    unarchived_count = 0
    errors = []

    capas.each do |capa|
      next unless can_manage_capa?(capa)
      begin
        capa.update_column(:archived, false)
        AuditLogService.log_action(
          actor_user: current_user,
          company: current_company,
          action: "UNARCHIVE_CAPA",
          entity_type: "capa",
          entity_id: capa.id,
          payload: { title: capa.title, bulk: true }
        )
        unarchived_count += 1
      rescue => e
        errors << I18n.t("capa_management_ui.notifications.unarchive_failed", id: capa.id, error: e.message)
      end
    end

    if unarchived_count > 0 && errors.empty?
      message = I18n.t("capa_management_ui.notifications.bulk_unarchive_success", count: unarchived_count)
      notification_html = render_to_string(partial: "shared/notification", locals: { message: message, type: :success, animated: true }, formats: [ :html ])
      render json: { message: message, notification_html: notification_html, unarchived_count: unarchived_count }
    elsif unarchived_count > 0
      message = I18n.t("capa_management_ui.notifications.bulk_unarchive_partial", count: unarchived_count, errors: errors.join(', '))
      notification_html = render_to_string(partial: "shared/notification", locals: { message: message, type: :success, animated: true }, formats: [ :html ])
      render json: { message: message, notification_html: notification_html, unarchived_count: unarchived_count, errors: errors }
    else
      error_message = I18n.t("capa_management_ui.notifications.bulk_unarchive_error", errors: errors.join(', '))
      notification_html = render_to_string(partial: "shared/notification", locals: { message: error_message, type: :error, animated: true }, formats: [ :html ])
      render json: { error: error_message, notification_html: notification_html }, status: :unprocessable_entity
    end
  end

  def bulk_delete
    unless current_company
      error_message = I18n.t("capa_management_ui.notifications.no_company_context")
      notification_html = render_to_string(partial: "shared/notification", locals: { message: error_message, type: :error, animated: true }, formats: [ :html ])
      render json: { error: error_message, notification_html: notification_html }, status: :unprocessable_entity and return
    end

    capa_ids = params[:capa_ids] || []
    if capa_ids.empty?
      error_message = I18n.t("capa_management_ui.notifications.no_capas_selected")
      notification_html = render_to_string(partial: "shared/notification", locals: { message: error_message, type: :error, animated: true }, formats: [ :html ])
      render json: { error: error_message, notification_html: notification_html }, status: :unprocessable_entity and return
    end

    capas = capa_visible_scope(base: Capa.where(company_id: current_company.id)).where(id: capa_ids)
    deleted_count = 0
    errors = []

    capas.each do |capa|
      next unless can_manage_capa?(capa)
      begin
        capa_title = capa.title
        capa_id = capa.id
        capa.destroy
        AuditLogService.log_action(
          actor_user: current_user,
          company: current_company,
          action: "DELETE_CAPA",
          entity_type: "capa",
          entity_id: capa_id,
          payload: { title: capa_title, bulk: true }
        )
        deleted_count += 1
      rescue => e
        errors << I18n.t("capa_management_ui.notifications.delete_failed", id: capa.id, error: e.message)
      end
    end

    if deleted_count > 0 && errors.empty?
      message = I18n.t("capa_management_ui.notifications.bulk_delete_success", count: deleted_count)
      notification_html = render_to_string(partial: "shared/notification", locals: { message: message, type: :success, animated: true }, formats: [ :html ])
      render json: { message: message, notification_html: notification_html, deleted_count: deleted_count }
    elsif deleted_count > 0
      message = I18n.t("capa_management_ui.notifications.bulk_delete_partial", count: deleted_count, errors: errors.join(', '))
      notification_html = render_to_string(partial: "shared/notification", locals: { message: message, type: :success, animated: true }, formats: [ :html ])
      render json: { message: message, notification_html: notification_html, deleted_count: deleted_count, errors: errors }
    else
      error_message = I18n.t("capa_management_ui.notifications.bulk_delete_error", errors: errors.join(', '))
      notification_html = render_to_string(partial: "shared/notification", locals: { message: error_message, type: :error, animated: true }, formats: [ :html ])
      render json: { error: error_message, notification_html: notification_html }, status: :unprocessable_entity
    end
  end

  private

  def ensure_company_selected
    if current_user&.platform_admin? && current_company.nil?
      redirect_to select_company_dashboard_capa_management_path
    end
  end

  def calculate_overview_statistics
    return {} unless current_company

    capas = capa_visible_scope(base: Capa.where(company_id: current_company.id).not_archived)

    {
      open_count: capas.where(status: "open").count,
      high_priority_count: capas.where(priority: "high").count,
      overdue_count: capas.where("due_date < ?", Date.today).where.not(status: :closed).where.not(due_date: nil).count,
      avg_resolution_days: calculate_avg_resolution_days(capas)
    }
  end

  def calculate_avg_resolution_days(capas)
    closed_capas = capas.where(status: "closed").where.not(created_at: nil, updated_at: nil)
    return 0 if closed_capas.empty?

    total_days = closed_capas.sum { |c| (c.updated_at.to_date - c.created_at.to_date).to_i }
    (total_days / closed_capas.count.to_f).round(1)
  rescue
    0
  end

  def questionnaire_complete?(questionnaire)
    return false unless questionnaire

    (1..5).all? do |num|
      questionnaire.send("question_#{num}").present? && questionnaire.send("answer_#{num}").present?
    end
  end

  def get_assigned_to_me_capa_row(capa)
    return nil unless current_user&.company_user && capa

    # Check if CAPA is assigned to current user
    assigned = capa.capa_assignments.exists?(company_user_id: current_user.company_user.id)
    return nil unless assigned

    # Get top 4 assigned to me CAPAs (within visible scope) to see if this one should be included
    assigned_capas = capa_visible_scope(base: Capa.where(company_id: current_company.id).not_archived)
                        .joins(:capa_assignments)
                        .where(capa_assignments: { company_user_id: current_user.company_user.id })
                        .includes(:standard, :company_users, :users)
                        .order(due_date: :asc, created_at: :desc)
                        .limit(4)
                        .distinct

    # Only include if it's in the top 4
    return nil unless assigned_capas.map(&:id).include?(capa.id)

    render_to_string(partial: "dashboard/capa_management/assigned_to_me_row",
                     locals: { capa: capa }, formats: [ :html ])
  rescue
    nil
  end

  def get_overdue_capa_row(capa)
    return nil unless capa

    # Check if CAPA is overdue
    return nil unless capa.due_date && capa.due_date < Date.today && !capa.closed?

    # Get top 4 overdue CAPAs (within visible scope) to see if this one should be included
    overdue_capas = capa_visible_scope(base: Capa.where(company_id: current_company.id)
                        .where("due_date < ?", Date.today)
                        .where.not(status: :closed)
                        .where.not(due_date: nil)
                        .not_archived)
                        .includes(:standard, :company_users, :users)
                        .order(due_date: :asc, created_at: :desc)
                        .limit(4)

    # Only include if it's in the top 4
    return nil unless overdue_capas.map(&:id).include?(capa.id)

    render_to_string(partial: "dashboard/capa_management/overdue_row",
                     locals: { capa: capa }, formats: [ :html ])
  rescue
    nil
  end

  def handle_assigned_to_open_transition!(capa, old_status, new_status)
    return nil unless old_status == "assigned" && new_status == "open"
    removed_users = remove_all_assignments_for(capa)
    return nil if removed_users.empty?
    "All assigned users were removed because the CAPA is now Open."
  end

  def remove_all_assignments_for(capa)
    assignments = capa.capa_assignments.includes(company_user: :user).to_a
    return [] if assignments.empty?

    assignment_ids = assignments.map(&:id)
    CapaAssignment.where(id: assignment_ids).delete_all
    capa.reload
    capa.sync_status_with_assignments

    assignments.each do |assignment|
      user = assignment.company_user&.user
      next unless user
      AuditLogService.log_action(
        actor_user: current_user,
        company: current_company,
        action: "UNASSIGN_USER_FROM_CAPA",
        entity_type: "capa",
        entity_id: capa.id,
        payload: {
          user_id: user.id,
          user_name: user.name
        }
      )
      NotificationService.notify_capa_unassigned(recipient: user, capa: capa, actor: current_user)
    end

    assignments.map { |assignment| assignment.company_user&.user }.compact
  end

  def generate_show_page_html(capa)
    return nil unless capa

    # Check if CAPA is overdue (has due_date and it's before today)
    is_overdue = capa.due_date.present? && capa.due_date < Date.today && !capa.closed?

    # Status styling
    status_styles = {
      "open" => { bg: "bg-[#FEF0FF]", text: "text-[#B130AC]", label: "Open" },
      "assigned" => { bg: "bg-[#E9F5F8]", text: "text-[#1B94AD]", label: "Assigned" },
      "in_progress" => { bg: "bg-[#E9F0FF]", text: "text-[#1751A7]", label: "In Progress" },
      "closed" => { bg: "bg-[#E0F9DE]", text: "text-[#3F9011]", label: "Closed" }
    }

    # Special cases for in_progress status
    if capa.status == "in_progress"
      if is_overdue
        status_style = { bg: "bg-[#FFF1F0]", text: "text-[#B13030]", label: "Overdue" }
      else
        status_style = { bg: "bg-[#F5FFD8]", text: "text-[#789C16]", label: "In Time" }
      end
    else
      status_style = status_styles[capa.status] || { bg: "bg-gray-100", text: "text-gray-600", label: capa.status&.humanize || "-" }
    end

    # Priority styling
    priority_styles = {
      "high" => "High Priority",
      "medium" => "Medium Priority",
      "low" => "Low Priority"
    }
    priority_label = priority_styles[capa.priority] || capa.priority&.humanize || "No Priority"

    # Format due date
    due_date_formatted = capa.due_date ? capa.due_date.strftime("%b %d, %Y") : nil

    # Source/Audit styling
    source_labels = {
      "internal_audit" => "Internal Audit",
      "external_audit" => "External Audit",
      "customer_complaint" => "Customer Complaint"
    }
    source_label = source_labels[capa.source] || capa.source&.humanize || "Audit"

    capa_code = capa.friendly_code

    {
      status_html: status_style[:label],
      status_bg: status_style[:bg],
      status_text: status_style[:text],
      due_date_html: due_date_formatted,
      priority_html: priority_label,
      source_html: source_label,
      capa_code_html: capa_code,
      standard_html: capa.standard ? capa.standard.display_name : nil,
      title_html: capa.title,
      description_html: capa.description,
      assignees: capa.company_users.includes(:user).map do |cu|
        {
          id: cu.id,
          name: cu.user.name,
          initial: cu.user.name&.first&.upcase || "?"
        }
      end
    }
  end

  def capa_params
    # Permit analysis_method now that it's in the database
    params.require(:capa).permit(:title, :description, :source, :standard_id, :priority, :due_date, :status, :analysis_method)
  end

  def capa_action_params
    params.require(:capa_action).permit(:title, :action_type, :status, :due_date, :notes)
  end

  # Restrict company user IDs to current company only (prevents assigning users from other companies)
  def allowed_company_user_ids_for_capa(ids)
    return [] if ids.blank? || current_company.blank?
    ids = Array(ids).reject(&:blank?).map(&:to_s).uniq
    CompanyUser.where(company_id: current_company.id, id: ids).pluck(:id)
  end

  # --- Role-based CAPA visibility and permissions ---
  # capa_visible_scope is defined in Dashboard::BaseController

  def can_create_capa?
    return true if current_user&.super_admin? || current_user&.delegated_admin?
    cu = current_user&.company_user
    return false unless cu
    cu.company_auditor? || cu.has_admin_privileges?
  end

  # Company admin, QM: full manage. Auditor: can manage CAPAs they created or are assigned to (edit, questionnaire, actions, mark action Done, etc.); company-scoped.
  def can_manage_capa?(capa)
    return true if current_user&.super_admin? || current_user&.delegated_admin?
    return false unless capa && capa_visible_scope(base: Capa.where(company_id: current_company.id)).exists?(capa.id)
    cu = current_user&.company_user
    return false unless cu && capa.company_id.present? && cu.company_id == capa.company_id
    return true if cu.company_admin? || cu.company_quality_manager?
    return true if cu.company_auditor? && (capa.created_by_id == current_user.id || capa.capa_assignments.exists?(company_user_id: cu.id))
    false
  end

  # Reverting CAPA from Assigned to Open (which removes all assignees) is allowed only for: QM of the company, company admin of the company, or auditor who created this CAPA.
  def can_revert_assigned_to_open?(capa)
    return true if current_user&.super_admin? || current_user&.delegated_admin?
    return false unless capa&.company_id.present?
    cu = current_user&.company_user
    return false unless cu && cu.company_id == capa.company_id
    return true if cu.company_admin? || cu.company_quality_manager?
    return true if cu.company_auditor? && capa.created_by_id == current_user.id
    false
  end

  # Only company admin or quality manager can close a CAPA; must be in the same company as the CAPA when capa is given.
  def can_close_capa?(capa = nil)
    return true if current_user&.super_admin? || current_user&.delegated_admin?
    cu = current_user&.company_user
    return false unless cu
    return false unless cu.company_admin? || cu.company_quality_manager?
    if capa&.company_id.present?
      return false unless cu.company_id == capa.company_id
    end
    true
  end

  # Company admin & QM: can. Contributor: only if CAPA is assigned to them. Auditor: if assigned to them or created by them.
  def can_link_documents_to_capa?(capa)
    return true if current_user&.super_admin? || current_user&.delegated_admin?
    return false unless capa
    cu = current_user&.company_user
    return false unless cu
    return true if cu.has_admin_privileges?
    assigned = capa.capa_assignments.exists?(company_user_id: cu.id)
    return true if cu.company_contributor? && assigned
    return true if cu.company_auditor? && (assigned || capa.created_by_id == current_user.id)
    false
  end

  # Only company admin, quality manager, or an auditor who created or is assigned to the CAPA
  # (plus global super/delegated admins) can view the CAPA activity log.
  def can_view_capa_activity_log?(capa)
    return false unless capa
    return true if current_user&.super_admin? || current_user&.delegated_admin?

    cu = current_user&.company_user
    return false unless cu && capa.company_id.present? && cu.company_id == capa.company_id

    return true if cu.company_admin? || cu.company_quality_manager? || cu.company_viewer?
    return true if cu.company_auditor? && (
      capa.created_by_id == current_user.id ||
      capa.capa_assignments.exists?(company_user_id: cu.id)
    )

    false
  end

  def assignee_of_capa_action?(capa_action)
    return true if current_user&.super_admin? || current_user&.delegated_admin?
    cu = current_user&.company_user
    return false unless cu && capa_action
    capa_action.capa_action_assignments.exists?(company_user_id: cu.id)
  end

  # Only assignees of this action, or company admin / QM, can link evidence to this CAPA action.
  # Contributors and auditors can only act on actions they are assigned to.
  def can_link_documents_to_capa_action?(capa_action)
    return true if current_user&.super_admin? || current_user&.delegated_admin?
    return false unless capa_action
    capa = capa_action.capa
    return false unless capa && capa_visible_scope(base: Capa.where(company_id: current_company&.id)).exists?(capa.id)
    cu = current_user&.company_user
    return false unless cu
    return true if cu.has_admin_privileges?
    return true if assignee_of_capa_action?(capa_action)
    false
  end

  # Contributors and auditors can upload evidence only for actions assigned to them; company admin / QM can always upload.
  def can_upload_evidence_to_capa_action?(capa_action)
    return true if current_user&.super_admin? || current_user&.delegated_admin?
    return false unless capa_action
    cu = current_user&.company_user
    return false unless cu
    return true if cu.has_admin_privileges?
    return true if assignee_of_capa_action?(capa_action)
    false
  end

  # Admin/QM: can always assign people to any action.
  # Auditor: can assign only if they created this action OR they have admin privileges.
  # Contributor/viewer: cannot assign.
  def can_assign_to_capa_action?(capa_action)
    return true if current_user&.super_admin? || current_user&.delegated_admin?
    return false unless capa_action
    cu = current_user&.company_user
    return false unless cu
    return true if cu.has_admin_privileges?
    return true if cu.company_auditor? && capa_action.created_by_id == current_user.id
    false
  end

  # Same as can_manage_capa? on the action's CAPA — used for updating action (e.g. status) from the action page.
  def can_update_capa_action?(capa_action)
    return false unless capa_action&.capa
    can_manage_capa?(capa_action.capa)
  end

  # Only company admin (in the CAPA's company) can delete comments or replies on a CAPA action.
  def can_delete_capa_action_comment?(capa)
    return true if current_user&.super_admin? || current_user&.delegated_admin?
    return false unless capa&.company_id.present?
    cu = current_user&.company_user
    return false unless cu && cu.company_id == capa.company_id
    cu.company_admin?
  end

  # For contributor: only actions they are assigned to.
  # For auditor assigned to the CAPA (or who created it): all actions of the CAPA.
  # For auditor NOT assigned to the CAPA: only actions they are assigned to.
  # For admin/QM: all actions of the CAPA.
  def capa_actions_visible_to_current_user(capa)
    return capa.capa_actions.none unless capa
    return capa.capa_actions if current_user&.super_admin? || current_user&.delegated_admin?
    cu = current_user&.company_user
    return capa.capa_actions.none unless cu && capa.company_id.present? && cu.company_id == capa.company_id
    return capa.capa_actions if cu.company_admin? || cu.company_quality_manager? || cu.company_viewer?
    # Auditor assigned to this CAPA (or who created it) sees all actions
    if cu.company_auditor?
      auditor_has_capa_access = capa.created_by_id == current_user.id ||
                                capa.capa_assignments.exists?(company_user_id: cu.id)
      return capa.capa_actions if auditor_has_capa_access
    end
    # Contributor or unassigned auditor: only actions where current user is assignee
    capa.capa_actions.joins(:capa_action_assignments).where(capa_action_assignments: { company_user_id: cu.id }).distinct
  end
end
