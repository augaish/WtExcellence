class UploadsController < DashboardController
  def new
    # Filter folders by company for non-platform-admin users
    if current_user&.platform_admin?
      @folders = Folder.all.order(:name)
    else
      company = current_company
      @folders = company ? Folder.where(company_id: company.id).where.not(company_id: nil).order(:name) : Folder.none
    end
    @upload = Upload.new
  end

  def create
    return if prevent_viewer_action
    # Get company for upload creation
    company_id = if current_user&.platform_admin?
      # Platform admins can create uploads for any company; default to folder's company or first company
      if upload_params[:folder_id].present?
        Folder.find_by(id: upload_params[:folder_id])&.company_id || Company.active.order(:created_at).first&.id
      else
        Company.active.order(:created_at).first&.id
      end
    else
      # Non-platform-admin users can only create uploads for their company
      current_company&.id
    end

    unless company_id
      render json: {
        success: false,
        message: "Unable to determine company. Please contact your administrator."
      }, status: :unprocessable_entity
      return
    end

    # Ensure folder (if provided) belongs to the upload's company - prevent cross-company uploads
    folder_id = upload_params[:folder_id].presence
    if folder_id.present?
      folder = Folder.find_by(id: folder_id)
      unless folder
        render json: {
          success: false,
          message: "Selected folder not found."
        }, status: :unprocessable_entity
        return
      end
      unless current_user&.platform_admin?
        if folder.company_id != company_id
          render json: {
            success: false,
            message: "You cannot upload to a folder from another company."
          }, status: :forbidden
          return
        end
      end
    end

    @upload = Upload.new(upload_params)
    @upload.company_id = company_id
    @upload.uploaded_by = current_user.id
    # Only set default visibility if not provided in params
    @upload.visibility = upload_params[:visibility].presence || "public"

    # Attach file if provided (must be done before validation)
    if params[:upload][:file].present?
      uploaded_file = params[:upload][:file]
      @upload.file.attach(uploaded_file)

      # Set file metadata
      @upload.filename = uploaded_file.original_filename
      @upload.mime_type = uploaded_file.content_type
      @upload.size_bytes = uploaded_file.size
    end

    # Validate CAPA/CapaAction belongs to upload's company and user has permission to attach
    capa_id = params[:capa_id].presence
    capa_action_id = params[:capa_action_id].presence
    if (capa_id.present? || capa_action_id.present?) && !current_user&.super_admin? && !current_user&.delegated_admin?
      if capa_action_id.present?
        action = CapaAction.joins(:capa).find_by(id: capa_action_id, capas: { company_id: company_id })
        unless action
          render json: { success: false, message: "You cannot link this upload to that action." }, status: :forbidden
          return
        end
        cu = current_user&.company_user
        unless cu && (cu.has_admin_privileges? || action.capa_action_assignments.exists?(company_user_id: cu.id))
          render json: { success: false, message: "Only assignees of this action or QM/Admin can attach files to it." }, status: :forbidden
          return
        end
      elsif capa_id.present?
        capa = Capa.find_by(id: capa_id)
        unless capa && capa.company_id == company_id
          render json: { success: false, message: "You cannot link this upload to that CAPA." }, status: :forbidden
          return
        end
        cu = current_user&.company_user
        unless cu
          render json: { success: false, message: "You do not have permission to attach files to this CAPA." }, status: :forbidden
          return
        end
        assigned = capa.capa_assignments.exists?(company_user_id: cu.id)
        allowed = cu.has_admin_privileges? ||
          (cu.company_contributor? && assigned) ||
          (cu.company_auditor? && (assigned || capa.created_by_id == current_user.id))
        unless allowed
          render json: { success: false, message: "You do not have permission to attach files to this CAPA." }, status: :forbidden
          return
        end
      end
    end

    # Set current user in Thread for activity logging (if uploading from CAPA)
    Thread.current[:current_user] = current_company_user&.user if capa_id.present? || capa_action_id.present?

    if @upload.save
      # Link to CAPA or CapaAction if provided (already validated above)
      if capa_action_id.present?
        action = CapaAction.joins(:capa).find_by(id: capa_action_id, capas: { company_id: company_id })
        if action && (current_user&.super_admin? || current_user&.delegated_admin? || action.capa.company_id == company_id)
          EvidenceAttachment.create!(attachable: action, upload: @upload, attached_by: current_company_user&.user&.id)
          doc_name = @upload.display_name.presence || @upload.filename
          NotificationService.notify_capa_evidence_attached(capa: action.capa, actor: current_user, document_name: doc_name)
          NotificationService.notify_auditors_capa_evidence_attached(capa: action.capa, capa_action: action, actor: current_user, document_name: doc_name)
        end
      elsif capa_id.present?
        capa = Capa.find_by(id: capa_id)
        if capa && (current_user&.super_admin? || current_user&.delegated_admin? || capa.company_id == company_id)
          EvidenceAttachment.create!(attachable: capa, upload: @upload, attached_by: current_company_user&.user&.id)
          doc_name = @upload.display_name.presence || @upload.filename
          NotificationService.notify_capa_evidence_attached(capa: capa, actor: current_user, document_name: doc_name)
          NotificationService.notify_auditors_capa_evidence_attached(capa: capa, actor: current_user, document_name: doc_name)
        end
      end

      # Generate notification HTML
      notification_html = render_to_string(
        partial: "shared/notification",
        locals: { message: t("document.upload_success"), type: :success, animated: true },
        formats: [ :html ]
      )

      render json: {
        success: true,
        message: t("document.upload_success"),
        notification_html: notification_html,
        upload: {
          id: @upload.id,
          name: @upload.display_name,
          filename: @upload.filename,
          mime_type: @upload.mime_type,
          notes: @upload.notes,
          created_at: @upload.created_at.strftime("%b %d, %Y"),
          file_url: helpers.signed_file_url(@upload.file, disposition: "attachment"),
          capa_id: capa_id
        }
      }, status: :created
    else
      notification_html = render_to_string(
        partial: "shared/notification",
        locals: { message: @upload.errors.full_messages.join(", "), type: :error, animated: true },
        formats: [ :html ]
      )

      render json: {
        success: false,
        message: @upload.errors.full_messages.join(", "),
        notification_html: notification_html
      }, status: :unprocessable_entity
    end
  ensure
    Thread.current[:current_user] = nil
  end

  def show
    @folder_id = params[:folder_id]
    @upload = Upload.find(params[:id])

    # Check if user can see this upload (visibility check)
    unless @upload.visible_to_user?(current_user)
      redirect_to library_path, alert: "You don't have access to this file."
      return
    end

    # Eager load attachables and their associations to avoid N+1 queries
    @linked_items = @upload.evidence_attachments.includes(:attachable).order(created_at: :desc)

    # Preload associations based on attachable type
    clauses = @linked_items.select { |a| a.attachable_type == "Clause" }.map(&:attachable).compact
    checklist_items = @linked_items.select { |a| a.attachable_type == "ChecklistItem" }.map(&:attachable).compact
    capas = @linked_items.select { |a| a.attachable_type == "Capa" }.map(&:attachable).compact

    ActiveRecord::Associations::Preloader.new(
      records: clauses,
      associations: [ :standard_version, :parent, :checklist_items, { standard_version: :standard } ]
    ).call if clauses.any?

    ActiveRecord::Associations::Preloader.new(
      records: checklist_items,
      associations: [ :clause, { clause: [ :standard_version, { standard_version: :standard } ] } ]
    ).call if checklist_items.any?

    ActiveRecord::Associations::Preloader.new(
      records: capas,
      associations: [ :standard ]
    ).call if capas.any?

    # Group linked items by Standard
    @grouped_by_standard = {}
    @ungrouped_items = [] # Items without a standard or items that should be isolated (e.g., Capas)

    @linked_items.each do |attachment|
      # Capas should always be isolated, regardless of whether they have a standard
      if attachment.attachable_type == "Capa"
        @ungrouped_items << attachment
        next
      end

      standard = case attachment.attachable_type
      when "Standard"
        attachment.attachable
      when "Clause"
        attachment.attachable&.standard_version&.standard
      when "ChecklistItem"
        attachment.attachable&.clause&.standard_version&.standard
      else
        nil
      end

      if standard
        @grouped_by_standard[standard.id] ||= {
          standard: standard,
          attachments: [],
          standard_attachment: nil
        }

        if attachment.attachable_type == "Standard"
          @grouped_by_standard[standard.id][:standard_attachment] = attachment
        else
          @grouped_by_standard[standard.id][:attachments] << attachment
        end
      else
        # Items without a standard
        @ungrouped_items << attachment
      end
    end

    # Validate folder_id matches upload's folder_id (or handle 'all' case)
    if @folder_id != "all" && @upload.folder_id.present? && @upload.folder_id.to_s != @folder_id
      redirect_to folder_uploads_upload_path(folder_id: @upload.folder_id || "all", id: @upload.id), alert: t("upload_not_in_folder")
      return
    end

    respond_to do |format|
      format.html # Render the attachment view page
      format.json { render json: upload_json(@upload) }
    end
  rescue ActiveRecord::RecordNotFound
    respond_to do |format|
      format.html { redirect_to (@folder_id && @folder_id != "all" ? folder_path(@folder_id) : library_path), alert: t("upload_not_found") }
      format.json { head :not_found }
    end
  end

  def update
    return if prevent_viewer_action
    @folder_id = params[:folder_id]
    @upload = Upload.find(params[:id])

    unless can_modify_upload?(@upload)
      respond_to do |format|
        format.html { redirect_to library_path, alert: "You don't have permission to edit this file.", status: :forbidden }
        format.json { render json: { success: false, errors: [ "You don't have permission to edit this file." ] }, status: :forbidden }
      end
      return
    end

    if @upload.update(upload_params)
      respond_to do |format|
        format.html { redirect_to folder_uploads_upload_path(folder_id: @folder_id, id: @upload.id), notice: t("upload_updated_successfully") }
        format.json { render json: { success: true, upload: upload_json(@upload) } }
      end
    else
      respond_to do |format|
        format.html {
          @linked_items = @upload.evidence_attachments.includes(:attachable).order(created_at: :desc)
          render :show, status: :unprocessable_entity
        }
        format.json { render json: { success: false, errors: @upload.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def update_visibility
    return if prevent_viewer_action
    @upload = Upload.find_by(id: params[:id])

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

    unless can_modify_upload?(@upload)
      notification_html = render_to_string(partial: "shared/notification", locals: { message: "You don't have permission to change this file's visibility.", type: :error, animated: true }, formats: [ :html ])
      render json: {
        success: false,
        message: "You don't have permission to change this file's visibility.",
        type: "error",
        notification_html: notification_html
      }, status: :forbidden
      return
    end

    new_visibility = params[:visibility]
    unless %w[public private].include?(new_visibility)
      notification_html = render_to_string(partial: "shared/notification", locals: { message: "Invalid visibility value.", type: :error, animated: true }, formats: [ :html ])
      render json: {
        success: false,
        message: "Invalid visibility value.",
        type: "error",
        notification_html: notification_html
      }, status: :unprocessable_entity
      return
    end

    if @upload.update(visibility: new_visibility)
      visibility_text = new_visibility == "public" ? "public" : "private"
      message = "File visibility changed to #{visibility_text} successfully."
      notification_html = render_to_string(partial: "shared/notification", locals: { message: message, type: :success, animated: true }, formats: [ :html ])

      render json: {
        success: true,
        message: message,
        type: "success",
        notification_html: notification_html,
        upload: {
          id: @upload.id,
          visibility: @upload.visibility
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
    @folder_id = params[:folder_id]
    @upload = Upload.find(params[:id])

    unless can_modify_upload?(@upload)
      notification_html = render_to_string(partial: "shared/notification", locals: { message: "You don't have permission to delete this file.", type: :error, animated: true }, formats: [ :html ])
      respond_to do |format|
        format.html { redirect_to library_path, alert: "You don't have permission to delete this file.", status: :forbidden }
        format.json { render json: { success: false, message: "You don't have permission to delete this file.", type: "error", notification_html: notification_html }, status: :forbidden }
      end
      return
    end

    upload_name = @upload.display_name
    if @upload.destroy
      notification_html = render_to_string(partial: "shared/notification", locals: { message: t("upload_deleted_successfully", name: upload_name), type: :success, animated: true }, formats: [ :html ])

      respond_to do |format|
        format.html { redirect_to (@folder_id && @folder_id != "all" ? folder_path(@folder_id) : library_path), notice: t("upload_deleted_successfully", name: upload_name) }
        format.json { render json: { success: true, message: t("upload_deleted_successfully", name: upload_name), type: "success", notification_html: notification_html } }
      end
    else
      notification_html = render_to_string(partial: "shared/notification", locals: { message: t("upload_delete_failed"), type: :error, animated: true }, formats: [ :html ])

      respond_to do |format|
        format.html { redirect_to folder_uploads_upload_path(folder_id: @folder_id, id: @upload.id), alert: t("upload_delete_failed") }
        format.json { render json: { success: false, message: t("upload_delete_failed"), type: "error", notification_html: notification_html }, status: :unprocessable_entity }
      end
    end
  end

  def download
    @folder_id = params[:folder_id]
    @upload = Upload.find(params[:id])

    unless @upload.visible_to_user?(current_user)
      redirect_to library_path, alert: "You don't have access to this file.", status: :forbidden
      return
    end

    if @upload.file.attached?
      redirect_to helpers.signed_file_url(@upload.file, disposition: "attachment"), allow_other_host: true
    else
      redirect_to folder_uploads_upload_path(folder_id: @folder_id, id: @upload.id), alert: t("file_not_available")
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to (@folder_id && @folder_id != "all" ? folder_path(@folder_id) : library_path), alert: t("upload_not_found")
  end

  def linked_items
    @folder_id = params[:folder_id]
    @upload = Upload.find(params[:id])

    unless @upload.visible_to_user?(current_user)
      render json: { error: "You don't have access to this file." }, status: :forbidden
      return
    end

    @linked_items = @upload.evidence_attachments.includes(:attachable).order(created_at: :desc)

    render json: {
      items: @linked_items.map do |attachment|
        {
          id: attachment.id,
          attachable_id: attachment.attachable_id,
          attachable_type: attachment.attachable_type,
          type_display: attachable_type_display(attachment.attachable_type),
          name: attachable_name(attachment),
          purpose: attachment.purpose,
          notes: attachment.notes,
          status: attachable_status(attachment.attachable),
          created_at: attachment.created_at.strftime("%b %d, %Y"),
          created_at_iso: attachment.created_at.iso8601
        }
      end
    }
  rescue ActiveRecord::RecordNotFound
    render json: { error: t("upload_not_found") }, status: :not_found
  end

  private

  def can_modify_upload?(upload)
    return false unless current_user && upload
    return true if current_user.super_admin? || current_user.delegated_admin?
    return true if upload.uploaded_by == current_user.id
    return true if current_user.company_user&.company_id == upload.company_id && current_user.company_user&.has_admin_privileges?
    false
  end

  def upload_params
    params.require(:upload).permit(:name, :notes, :folder_id, :file, :visibility)
  end

  def upload_json(upload)
    {
      id: upload.id,
      filename: upload.filename,
      name: upload.name,
      notes: upload.notes,
      mime_type: upload.mime_type,
      size_bytes: upload.size_bytes,
      size_formatted: format_file_size(upload.size_bytes),
      uploaded_by: upload.uploader&.name || (upload.uploaded_by.present? ? t("deleted_user", default: "Deleted user") : t("unknown_user")),
      folder_id: upload.folder_id,
      folder_name: upload.folder&.name,
      created_at: upload.created_at.strftime("%b %d, %Y"),
      created_at_iso: upload.created_at.iso8601,
      updated_at: upload.updated_at.strftime("%b %d, %Y"),
      file_attached: upload.file.attached?,
      file_url: helpers.signed_file_url(upload.file, disposition: "attachment")
    }
  end

  def format_file_size(bytes)
    return "0 B" if bytes.nil? || bytes == 0

    units = [ "B", "KB", "MB", "GB", "TB" ]
    unit_index = 0
    size = bytes.to_f

    while size >= 1024 && unit_index < units.length - 1
      size /= 1024
      unit_index += 1
    end

    "#{size.round(1)} #{units[unit_index]}"
  end

  def attachable_type_display(type)
    case type
    when "Standard" then "Standard"
    when "Clause" then "Clause"
    when "ChecklistItem" then "Checkpoint"
    when "Ticket" then "Ticket"
    when "Capa" then "CAPA"
    else type
    end
  end

  def attachable_name(attachment)
    return "Unknown" unless attachment.attachable

    case attachment.attachable_type
    when "Standard"
      attachment.attachable.display_name rescue attachment.attachable.code
    when "Clause"
      attachment.attachable.title rescue attachment.attachable.code
    when "ChecklistItem"
      attachment.attachable.text rescue attachment.attachable.code
    when "Capa"
      capa = attachment.attachable
      capa_code = capa.friendly_code
      "#{capa_code} — #{capa.title}"
    else
      attachment.notes.presence || "#{attachment.attachable_type} ##{attachment.attachable_id.to_s[0..7]}"
    end
  end

  def attachable_status(attachable)
    return nil unless attachable

    # Try to get status from various models
    if attachable.respond_to?(:status)
      attachable.status
    elsif attachable.respond_to?(:published?)
      attachable.published? ? "Published" : "Draft"
    else
      nil
    end
  end
end
