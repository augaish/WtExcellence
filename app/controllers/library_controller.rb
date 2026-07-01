class LibraryController < DashboardController
  before_action :ensure_not_risk_manager_only

  def index
    # For super admins and delegated admins, show company selection if no company_id is provided
    if (current_user&.super_admin? || current_user&.delegated_admin?) && params[:company_id].blank?
      @companies = Company.includes(:company_users).order(:name)
      @show_companies = true
      @folders_for_upload = Folder.none
      return
    end

    # Determine which company to show
    company = if current_user&.super_admin? || current_user&.delegated_admin?
      # Super admin or delegated admin can view any company's library
      Company.find_by(id: params[:company_id]) if params[:company_id].present?
    else
      # Regular users see their own company's library
      current_company
    end

    # If no company found, redirect to companies list for super admins/delegated admins
    if (current_user&.super_admin? || current_user&.delegated_admin?) && company.nil?
      redirect_to library_path, alert: "Company not found."
      return
    end

    # Filter folders by company
    if company
      @company = company
      @folders = Folder.where(company_id: company.id).where.not(company_id: nil).root_folders
    else
      @folders = Folder.none
    end

    @search_query = params[:search]&.strip
    @sort = params[:sort] || "last_modified"

    # Reset page to 1 when search query changes (but not when just changing pages)
    if params[:search].present? && params[:search] != session[:last_search]
      # Force page to 1 when search changes by removing page param
      params[:page] = nil
      session[:last_search] = params[:search]
    elsif params[:search].blank?
      session[:last_search] = nil
    end

    # Apply search filter
    @folders = @folders.where("name ILIKE ?", "%#{@search_query}%") if @search_query.present?

    # Apply sorting
    @folders = case @sort
    when "name_asc"
      @folders.order(name: :asc)
    when "name_desc"
      @folders.order(name: :desc)
    when "last_modified"
      @folders.order(updated_at: :desc)
    else
      @folders.order(updated_at: :desc)
    end

    # Paginate the filtered/searched results
    @pagy, @folders = pagy(@folders, limit: 7)

    # Folders for upload dialog (company-scoped so company admins only see their company's folders)
    @folders_for_upload = @company ? Folder.where(company_id: @company.id).where.not(company_id: nil).order(:name) : Folder.none

    # Evidence reuse dashboard — top 10 most-linked documents for this company
    if @company
      @top_reused_uploads = Upload.for_company(@company.id)
        .with_reuse_count
        .order("reuse_count DESC")
        .limit(10)
    end
  end

  def create
    return if prevent_viewer_action
    # Get company for folder creation
    company_id = if current_user&.super_admin? || current_user&.delegated_admin?
      # Super admin or delegated admin can create folders for any company
      # Use company_id from params if provided, otherwise use current company or first company
      params[:company_id].presence || params.dig(:folder, :company_id).presence || current_company&.id || Company.active.order(:created_at).first&.id
    else
      # Non-super-admin users can only create folders for their company
      current_company&.id
    end

    unless company_id
      notification_html = render_to_string(partial: "shared/notification", locals: { message: "Unable to determine company. Please contact your administrator.", type: :error, animated: true }, formats: [ :html ])
      render json: {
        success: false,
        message: "Unable to determine company.",
        type: "error",
        notification_html: notification_html
      }, status: :unprocessable_entity
      return
    end

    parent_id = folder_params[:parent_id].presence

    # Validate parent folder if provided
    if parent_id.present?
      parent_folder = Folder.find_by(id: parent_id)
      unless parent_folder
        notification_html = render_to_string(partial: "shared/notification", locals: { message: "Parent folder not found.", type: :error, animated: true }, formats: [ :html ])
        render json: {
          success: false,
          message: "Parent folder not found.",
          type: "error",
          notification_html: notification_html
        }, status: :not_found
        return
      end

      # Check if user has access to parent folder's company
      unless current_user&.super_admin? || current_user&.delegated_admin?
        if company_id.nil? || parent_folder.company_id.nil? || parent_folder.company_id != company_id
          notification_html = render_to_string(partial: "shared/notification", locals: { message: "You don't have access to the parent folder.", type: :error, animated: true }, formats: [ :html ])
          render json: {
            success: false,
            message: "You don't have access to the parent folder.",
            type: "error",
            notification_html: notification_html
          }, status: :forbidden
          return
        end
      end
    end

    @folder = Folder.new(
      name: folder_params[:folder_name],
      description: folder_params[:folder_description],
      company_id: company_id,
      created_by: current_user.id,
      color: folder_params[:color] || "#5C3984",
      parent_id: parent_id
    )

    if @folder.save
      notification_html = render_to_string(partial: "shared/notification", locals: { message: t("folder_created_successfully"), type: :success, animated: true }, formats: [ :html ])

      render json: {
        success: true,
        message: t("folder_created_successfully"),
        type: "success",
        notification_html: notification_html,
        folder: {
          id: @folder.id,
          name: @folder.name,
          description: @folder.description,
          file_count: @folder.file_count,
          updated_at: @folder.updated_at.strftime("%b %d, %Y"),
          color: @folder.color,
          parent_id: @folder.parent_id
        }
      }, status: :created
    else
      notification_html = render_to_string(partial: "shared/notification", locals: { message: @folder.errors.full_messages.join(", "), type: :error, animated: true }, formats: [ :html ])

      render json: {
        success: false,
        message: @folder.errors.full_messages.join(", "),
        type: "error",
        notification_html: notification_html
      }, status: :unprocessable_entity
    end
  end

  def show
    # Determine which company to show
    company = if current_user&.super_admin? || current_user&.delegated_admin?
      # Super admin or delegated admin can view any company's library
      # Try to get company_id from params or from folder's company
      if params[:company_id].present?
        Company.find_by(id: params[:company_id])
      elsif params[:id] != "all" && params[:id] != "legal_documents"
        # If viewing a specific folder, get company from folder
        folder = Folder.find_by(id: params[:id])
        folder&.company
      else
        nil
      end
    else
      # Regular users see their own company's library
      current_company
    end

    @company = company

    # Restrict standard_id/capa_id filters to company resources for non–super-admins (prevents probing other companies)
    allowed_standard_id = nil
    if params[:standard_id].present?
      sid = params[:standard_id].to_i
      allowed_standard_id = if current_user&.super_admin? || current_user&.delegated_admin?
        sid
      elsif company && CompanyStandard.exists?(standard_id: sid, company_id: company.id)
        sid
      end
    end
    allowed_capa_id = nil
    if params[:capa_id].present?
      cid = params[:capa_id].to_i
      allowed_capa_id = if current_user&.super_admin? || current_user&.delegated_admin?
        cid
      elsif company && Capa.exists?(id: cid, company_id: company.id)
        cid
      end
    end

    # Load folders for move file dialog (filtered by company)
    if current_user&.super_admin? || current_user&.delegated_admin?
      if company
        @all_folders = Folder.where(company_id: company.id).where.not(company_id: nil).order(:name)
      else
        @all_folders = Folder.none
      end
    else
      @all_folders = company ? Folder.where(company_id: company.id).where.not(company_id: nil).order(:name) : Folder.none
    end

    # Folders for upload dialog (company-scoped; never show other companies' folders)
    @folders_for_upload = company ? Folder.where(company_id: company.id).where.not(company_id: nil).order(:name) : Folder.none

    # When viewing Legal Documents, uploads go there (no folder choice; visibility forced to private)
    @upload_to_legal_documents = (params[:id] == "legal_documents")

    # Load company standards for filter dropdown
    if current_user&.super_admin? || current_user&.delegated_admin?
      # For super admins and delegated admins, show all standards
      @current_company_standards = Standard.all.includes(:standard_translations).order(:code).map do |standard|
        {
          id: standard.id,
          name: standard.display_name(I18n.locale.to_s),
          code: standard.code
        }
      end
    elsif company
      @current_company_standards = CompanyStandard.where(company_id: company.id)
        .includes(standard: :standard_translations)
        .order(created_at: :desc)
        .map do |company_standard|
          {
            id: company_standard.standard.id,
            name: company_standard.standard.display_name(I18n.locale.to_s),
            code: company_standard.standard.code
          }
        end
    else
      @current_company_standards = []
    end

    # Load company CAPAs for filter dropdown
    if current_user&.super_admin? || current_user&.delegated_admin?
      # For super admins and delegated admins, show all CAPAs
      @current_company_capas = Capa.all.not_archived.order(created_at: :desc).map do |capa|
        {
          id: capa.id,
          title: capa.title
        }
      end
    elsif company
      @current_company_capas = Capa.where(company_id: company.id).not_archived.order(created_at: :desc).map do |capa|
        {
          id: capa.id,
          title: capa.title
        }
      end
    else
      @current_company_capas = []
    end

    # Handle "All Uploaded Documents" special case
    if params[:id] == "all"
      @folder = nil
      @folder_name = t("all_uploaded_documents")
      # Filter uploads by visibility and company
      # Exclude private files (they should only appear in Legal Documents)
      if current_user&.super_admin? || current_user&.delegated_admin?
        if company
          @uploads = Upload.where(company_id: company.id)
                        .where.not(company_id: nil)
                        .where(visibility: "public")
                        .includes(:folder, :uploader)
                        .order(updated_at: :desc)
        else
          @uploads = Upload.where(visibility: "public")
                        .includes(:folder, :uploader)
                        .order(updated_at: :desc)
        end
      elsif company
        @uploads = Upload.visible_to_user(current_user)
                      .where(company_id: company.id)
                      .where.not(company_id: nil)
                      .where(visibility: "public")
                      .includes(:folder, :uploader)
                      .order(updated_at: :desc)
      else
        @uploads = Upload.visible_to_user(current_user)
                      .where(visibility: "public")
                      .includes(:folder, :uploader)
                      .order(updated_at: :desc)
      end

      # Note: Search is only for subfolders, not files

      # Apply standard filter (only when allowed for current company)
      if allowed_standard_id.present?
        @uploads = @uploads.joins(:evidence_attachments)
          .where(evidence_attachments: { attachable_type: "Standard", attachable_id: allowed_standard_id })
          .distinct
      end

      # Apply CAPA filter (only when allowed for current company)
      if allowed_capa_id.present?
        @uploads = @uploads.joins(:evidence_attachments)
          .where(evidence_attachments: { attachable_type: "Capa", attachable_id: allowed_capa_id })
          .distinct
      end
    elsif params[:id] == "legal_documents"
      # Handle "Legal Documents" special case - only visible to super admin and company admins
      unless current_user&.super_admin? || current_user&.delegated_admin? || current_user&.company_user&.has_admin_privileges?
        redirect_to library_path, alert: "You don't have access to legal documents."
        return
      end

      @folder = nil
      @folder_name = t("legal_documents")
      # Filter uploads to only show private uploads, restricted by company
      if current_user&.super_admin? || current_user&.delegated_admin?
        if company
          @uploads = Upload.where(company_id: company.id)
                        .where.not(company_id: nil)
                        .where(visibility: "private")
                        .includes(:folder, :uploader)
                        .order(updated_at: :desc)
        else
          @uploads = Upload.where(visibility: "private")
                        .includes(:folder, :uploader)
                        .order(updated_at: :desc)
        end
      elsif company
        # Company admins can see all private uploads in their company
        @uploads = Upload.where(company_id: company.id)
                      .where.not(company_id: nil)
                      .where(visibility: "private")
                      .includes(:folder, :uploader)
                      .order(updated_at: :desc)
      else
        @uploads = Upload.none
      end

      # Apply standard filter (only when allowed for current company)
      if allowed_standard_id.present?
        @uploads = @uploads.joins(:evidence_attachments)
          .where(evidence_attachments: { attachable_type: "Standard", attachable_id: allowed_standard_id })
          .distinct
      end

      # Apply CAPA filter (only when allowed for current company)
      if allowed_capa_id.present?
        @uploads = @uploads.joins(:evidence_attachments)
          .where(evidence_attachments: { attachable_type: "Capa", attachable_id: allowed_capa_id })
          .distinct
      end
    else
      @folder = Folder.find_by(id: params[:id])
      if @folder.nil?
        redirect_to library_path, alert: t("folder_not_found")
        return
      end

      # Check if user has access to this folder's company
      unless current_user&.super_admin? || current_user&.delegated_admin?
        if company.nil? || @folder.company_id.nil? || @folder.company_id != company.id
          redirect_to library_path, alert: "You don't have access to this folder."
          return
        end
      end

      @folder_name = @folder.name
      # Get uploads for this folder, filtered by visibility
      if current_user&.super_admin? || current_user&.delegated_admin?
        @uploads = @folder.uploads.includes(:folder, :uploader).order(updated_at: :desc)
      else
        @uploads = @folder.uploads.visible_to_user(current_user).includes(:folder, :uploader).order(updated_at: :desc)
      end

      # Apply standard filter (only when allowed for current company)
      if allowed_standard_id.present?
        @uploads = @uploads.joins(:evidence_attachments)
          .where(evidence_attachments: { attachable_type: "Standard", attachable_id: allowed_standard_id })
          .distinct
      end

      # Apply CAPA filter (only when allowed for current company)
      if allowed_capa_id.present?
        @uploads = @uploads.joins(:evidence_attachments)
          .where(evidence_attachments: { attachable_type: "Capa", attachable_id: allowed_capa_id })
          .distinct
      end

      # Eager load children for display
      @folder = Folder.includes(:children).find(@folder.id)
    end

    # Get view preference (list or grid, default to list)
    @current_view = params[:view] || session[:folder_view] || "list"
    session[:folder_view] = @current_view

    # Map uploads to the format expected by the view
    @files = @uploads.map do |upload|
      {
        id: upload.id,
        upload: upload, # Store the full object for access
        name: upload.display_name,
        description: upload.notes&.truncate(50) || "",
        type: file_type_from_mime(upload.mime_type),
        folder: upload.folder&.name || t("no_folder"),
        uploaded_by: upload.uploader&.name || (upload.uploaded_by.present? ? t("deleted_user", default: "Deleted user") : t("unknown_user")),
        last_modified: upload.updated_at&.strftime("%Y-%m-%d"),
        linked_to: upload.evidence_attachments.includes(:attachable).reject { |a| a.attachable_type == "CapaAction" }.map do |attachment|
          url = case attachment.attachable_type
          when "Standard"
                  standard_path(attachment.attachable_id) rescue "#"
          when "Clause"
                  standard_path(attachment.attachable.standard_id) rescue "#"
          when "ChecklistItem"
                  "#"
          when "Capa"
                  dashboard_capa_management_show_path(attachment.attachable_id) rescue "#"
          when "Assessment"
                  clause = attachment.attachable&.tool_clause&.clause
                  clause ? clause_assessment_path(clause) : "#"
          else
                  "#"
          end
          {
            name: attachment.attachable_name(I18n.locale.to_s),
            url: url
          }
        end
      }
    end
  end

  def move_file
    return if prevent_viewer_action
    @upload = Upload.find_by(id: params[:upload_id])

    unless @upload
      notification_html = render_to_string(partial: "shared/notification", locals: { message: "File not found.", type: :error, animated: true }, formats: [ :html ])
      render json: {
        success: false,
        message: "File not found.",
        type: "error",
        notification_html: notification_html
      }, status: :not_found
      return
    end

    # Check if user has access to this upload's company and can modify it (visibility)
    unless current_user&.super_admin? || current_user&.delegated_admin?
      company = current_company
      if company.nil? || @upload.company_id.nil? || @upload.company_id != company.id
        notification_html = render_to_string(partial: "shared/notification", locals: { message: "You don't have access to this file.", type: :error, animated: true }, formats: [ :html ])
        render json: {
          success: false,
          message: "You don't have access to this file.",
          type: "error",
          notification_html: notification_html
        }, status: :forbidden
        return
      end
      unless @upload.visible_to_user?(current_user)
        notification_html = render_to_string(partial: "shared/notification", locals: { message: "You don't have access to this file.", type: :error, animated: true }, formats: [ :html ])
        render json: {
          success: false,
          message: "You don't have access to this file.",
          type: "error",
          notification_html: notification_html
        }, status: :forbidden
        return
      end
    end

    new_folder_id = params[:folder_id].presence
    old_folder_name = @upload.folder&.name || "No folder"

    # Validate folder exists if provided
    if new_folder_id.present?
      new_folder = Folder.find_by(id: new_folder_id)
      unless new_folder
        notification_html = render_to_string(partial: "shared/notification", locals: { message: "Destination folder not found.", type: :error, animated: true }, formats: [ :html ])
        render json: {
          success: false,
          message: "Destination folder not found.",
          type: "error",
          notification_html: notification_html
        }, status: :not_found
        return
      end

      # Check if user has access to the destination folder's company
      unless current_user&.super_admin? || current_user&.delegated_admin?
        company = current_company
        if company.nil? || new_folder.company_id.nil? || new_folder.company_id != company.id
          notification_html = render_to_string(partial: "shared/notification", locals: { message: "You don't have access to the destination folder.", type: :error, animated: true }, formats: [ :html ])
          render json: {
            success: false,
            message: "You don't have access to the destination folder.",
            type: "error",
            notification_html: notification_html
          }, status: :forbidden
          return
        end
      end

      new_folder_name = new_folder.name
    else
      new_folder_name = "No folder"
    end

    # Update the upload's folder
    @upload.folder_id = new_folder_id

    if @upload.save
      message = if new_folder_id.present?
        "File '#{@upload.display_name}' moved to '#{new_folder_name}' successfully."
      else
        "File '#{@upload.display_name}' removed from folder successfully."
      end

      notification_html = render_to_string(partial: "shared/notification", locals: { message: message, type: :success, animated: true }, formats: [ :html ])

      render json: {
        success: true,
        message: message,
        type: "success",
        notification_html: notification_html,
        upload: {
          id: @upload.id,
          folder_id: @upload.folder_id,
          folder_name: @upload.folder&.name || "No folder"
        }
      }, status: :ok
    else
      notification_html = render_to_string(partial: "shared/notification", locals: { message: @upload.errors.full_messages.join(", "), type: :error, animated: true }, formats: [ :html ])

      render json: {
        success: false,
        message: @upload.errors.full_messages.join(", "),
        type: "error",
        notification_html: notification_html
      }, status: :unprocessable_entity
    end
  end

  def destroy
    return if prevent_viewer_action
    @folder = Folder.find_by(id: params[:id])

    unless @folder
      notification_html = render_to_string(partial: "shared/notification", locals: { message: t("folder_not_found"), type: :error, animated: true }, formats: [ :html ])
      render json: {
        success: false,
        message: t("folder_not_found"),
        type: "error",
        notification_html: notification_html
      }, status: :not_found
      return
    end

    # Check if user has access to this folder's company
    unless current_user&.super_admin? || current_user&.delegated_admin?
      company = current_company
      if company.nil? || @folder.company_id.nil? || @folder.company_id != company.id
        notification_html = render_to_string(partial: "shared/notification", locals: { message: "You don't have access to this folder.", type: :error, animated: true }, formats: [ :html ])
        render json: {
          success: false,
          message: "You don't have access to this folder.",
          type: "error",
          notification_html: notification_html
        }, status: :forbidden
        return
      end
    end

    folder_name = @folder.name
    file_count = @folder.file_count

    if @folder.destroy
      notification_html = render_to_string(partial: "shared/notification", locals: { message: t("folder_deleted_successfully", folder_name: folder_name), type: :success, animated: true }, formats: [ :html ])

      render json: {
        success: true,
        message: t("folder_deleted_successfully", folder_name: folder_name),
        type: "success",
        notification_html: notification_html
      }, status: :ok
    else
      notification_html = render_to_string(partial: "shared/notification", locals: { message: t("folder_delete_failed"), type: :error, animated: true }, formats: [ :html ])

      render json: {
        success: false,
        message: t("folder_delete_failed"),
        type: "error",
        notification_html: notification_html
      }, status: :unprocessable_entity
    end
  end



  def update_color
    return if prevent_viewer_action
    @folder = Folder.find_by(id: params[:id])

    unless @folder
      notification_html = render_to_string(partial: "shared/notification", locals: { message: t("folder_not_found"), type: :error, animated: true }, formats: [ :html ])
      render json: {
        success: false,
        message: t("folder_not_found"),
        type: "error",
        notification_html: notification_html
      }, status: :not_found
      return
    end

    # Check if user has access to this folder's company
    unless current_user&.super_admin? || current_user&.delegated_admin?
      company = current_company
      if company.nil? || @folder.company_id.nil? || @folder.company_id != company.id
        notification_html = render_to_string(partial: "shared/notification", locals: { message: "You don't have access to this folder.", type: :error, animated: true }, formats: [ :html ])
        render json: {
          success: false,
          message: "You don't have access to this folder.",
          type: "error",
          notification_html: notification_html
        }, status: :forbidden
        return
      end
    end

    if @folder.update(color: params[:color])
      notification_html = render_to_string(partial: "shared/notification", locals: { message: t("folder_color_updated"), type: :success, animated: true }, formats: [ :html ])

      render json: {
        success: true,
        message: t("folder_color_updated"),
        type: "success",
        notification_html: notification_html,
        folder: {
          id: @folder.id,
          color: @folder.color
        }
      }, status: :ok
    else
      notification_html = render_to_string(partial: "shared/notification", locals: { message: @folder.errors.full_messages.join(", "), type: :error, animated: true }, formats: [ :html ])

      render json: {
        success: false,
        message: @folder.errors.full_messages.join(", "),
        type: "error",
        notification_html: notification_html
      }, status: :unprocessable_entity
    end
  end

  def move
    return if prevent_viewer_action
    @folder = Folder.find_by(id: params[:id])

    unless @folder
      notification_html = render_to_string(partial: "shared/notification", locals: { message: t("folder_not_found"), type: :error, animated: true }, formats: [ :html ])
      render json: {
        success: false,
        message: t("folder_not_found"),
        type: "error",
        notification_html: notification_html
      }, status: :not_found
      return
    end

    # Check if user has access to this folder's company
    company = (current_user&.super_admin? || current_user&.delegated_admin?) ? nil : current_company
    unless current_user&.super_admin? || current_user&.delegated_admin?
      if company.nil? || @folder.company_id.nil? || @folder.company_id != company.id
        notification_html = render_to_string(partial: "shared/notification", locals: { message: "You don't have access to this folder.", type: :error, animated: true }, formats: [ :html ])
        render json: {
          success: false,
          message: "You don't have access to this folder.",
          type: "error",
          notification_html: notification_html
        }, status: :forbidden
        return
      end
    end

    new_parent_id = params[:parent_id].presence

    # Validate new parent folder if provided
    if new_parent_id.present?
      new_parent = Folder.find_by(id: new_parent_id)
      unless new_parent
        notification_html = render_to_string(partial: "shared/notification", locals: { message: "Destination folder not found.", type: :error, animated: true }, formats: [ :html ])
        render json: {
          success: false,
          message: "Destination folder not found.",
          type: "error",
          notification_html: notification_html
        }, status: :not_found
        return
      end

      # Check if user has access to the destination folder's company
      unless current_user&.super_admin? || current_user&.delegated_admin?
        if company.nil? || new_parent.company_id.nil? || new_parent.company_id != company.id
          notification_html = render_to_string(partial: "shared/notification", locals: { message: "You don't have access to the destination folder.", type: :error, animated: true }, formats: [ :html ])
          render json: {
            success: false,
            message: "You don't have access to the destination folder.",
            type: "error",
            notification_html: notification_html
          }, status: :forbidden
          return
        end
      end

      # Validate: Cannot move folder to itself
      if @folder.id == new_parent.id
        notification_html = render_to_string(partial: "shared/notification", locals: { message: "Cannot move folder to itself.", type: :error, animated: true }, formats: [ :html ])
        render json: {
          success: false,
          message: "Cannot move folder to itself.",
          type: "error",
          notification_html: notification_html
        }, status: :unprocessable_entity
        return
      end

      # Validate: Cannot move folder into its own child (prevent circular reference)
      if new_parent.ancestors.include?(@folder)
        notification_html = render_to_string(partial: "shared/notification", locals: { message: "Cannot move folder into its own subfolder. This would create a circular reference.", type: :error, animated: true }, formats: [ :html ])
        render json: {
          success: false,
          message: "Cannot move folder into its own subfolder. This would create a circular reference.",
          type: "error",
          notification_html: notification_html
        }, status: :unprocessable_entity
        return
      end
    end

    # Update the folder's parent
    @folder.parent_id = new_parent_id

    if @folder.save
      message = if new_parent_id.present?
        "Folder '#{@folder.name}' moved to '#{new_parent.name}' successfully."
      else
        "Folder '#{@folder.name}' moved to root level successfully."
      end

      notification_html = render_to_string(partial: "shared/notification", locals: { message: message, type: :success, animated: true }, formats: [ :html ])

      render json: {
        success: true,
        message: message,
        type: "success",
        notification_html: notification_html,
        folder: {
          id: @folder.id,
          parent_id: @folder.parent_id,
          parent_name: @folder.parent&.name || "Root"
        }
      }, status: :ok
    else
      notification_html = render_to_string(partial: "shared/notification", locals: { message: @folder.errors.full_messages.join(", "), type: :error, animated: true }, formats: [ :html ])

      render json: {
        success: false,
        message: @folder.errors.full_messages.join(", "),
        type: "error",
        notification_html: notification_html
      }, status: :unprocessable_entity
    end
  end

  private

  def file_type_from_mime(mime_type)
    return "Unknown" unless mime_type.present?

    case mime_type
    when /pdf/
      "PDF"
    when /excel|spreadsheet|\.xls|xlsx|application\/vnd\.openxmlformats-officedocument\.spreadsheetml\.sheet|application\/vnd\.ms-excel/
      "Excel"
    when /word|document|\.doc|docx|application\/vnd\.openxmlformats-officedocument\.wordprocessingml\.document|application\/msword/
      "Word"
    when /image/
      "Image"
    when /text/
      "Text"
    when /email|message/
      "Email"
    else
      "File"
    end
  end


  def folder_params
    params.require(:folder).permit(:folder_name, :folder_description, :color, :parent_id).to_h
  end
end
