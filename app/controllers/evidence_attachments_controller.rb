class EvidenceAttachmentsController < DashboardController
  before_action :prevent_viewer_actions, only: [ :create, :destroy ]

  private

  def prevent_viewer_actions
    nil if prevent_viewer_action
  end

  public

  def create
    # Restrict upload to documents the current user can access (company-scoped for non–super-admins)
    @upload = Upload.visible_to_user(current_user).find(params[:upload_id])

    # Non–super-admins must have a company context
    unless current_user&.super_admin? || current_user&.delegated_admin?
      if current_company.blank?
        respond_to do |format|
          format.json { render json: { success: false, error: t("upload_not_found") }, status: :forbidden }
        end
        return
      end
    end

    # Get attachable items from params
    items = params[:items] || []

    created_count = 0
    errors = []
    linked_attachments = []

    items.each do |item_params|
      attachable_type = item_params[:type]
      attachable_id = item_params[:id]

      # Validate attachable_type (CapaAction = attach to a specific corrective/preventive action)
      unless %w[Standard Clause ChecklistItem Capa CapaAction Risk Vendor CustomerCommitment].include?(attachable_type)
        errors << "Invalid type: #{attachable_type}"
        next
      end

      # Ensure attachable belongs to current user's company (prevents linking to other companies' resources)
      unless attachable_accessible_to_current_company?(attachable_type, attachable_id)
        errors << "You don't have access to #{attachable_type} #{attachable_id}"
        next
      end

      # Check if attachment already exists
      existing = EvidenceAttachment.find_by(
        upload_id: @upload.id,
        attachable_type: attachable_type,
        attachable_id: attachable_id
      )

      if existing
        errors << "#{attachable_type} #{attachable_id} is already linked"
        next
      end

      # Create the evidence attachment
      attachment = EvidenceAttachment.new(
        upload: @upload,
        attachable_type: attachable_type,
        attachable_id: attachable_id,
        attached_by: current_user&.id || session[:user_id] || SecureRandom.uuid
      )

      if attachment.save
        created_count += 1
        linked_attachments << attachment
      else
        errors << attachment.errors.full_messages.join(", ")
      end
    end

    # Log audit actions for successfully linked attachments
    linked_attachments.each do |attachment|
      company = @upload.company || extract_company_from_attachable(attachment.attachable_type, attachment.attachable_id) || current_company
      next unless company && current_user

      attachable_name = attachment.attachable_name rescue "Unknown"
      AuditLogService.log_action(
        actor_user: current_user,
        company: company,
        action: "LINK_DOCUMENT_TO_#{attachment.attachable_type.upcase}",
        entity_type: attachment.attachable_type.downcase,
        entity_id: attachment.attachable_id,
        payload: {
          upload_id: @upload.id,
          upload_name: @upload.display_name,
          upload_filename: @upload.filename,
          attachable_type: attachment.attachable_type,
          attachable_id: attachment.attachable_id,
          attachable_name: attachable_name
        }
      )

      # Notify CAPA assignees and auditors when evidence is attached to a CAPA or CapaAction
      if attachment.attachable_type == "Capa" && attachment.attachable_id.present?
        capa = Capa.find_by(id: attachment.attachable_id)
        if capa
          doc_name = @upload.display_name.presence || @upload.filename
          NotificationService.notify_capa_evidence_attached(capa: capa, actor: current_user, document_name: doc_name)
          NotificationService.notify_auditors_capa_evidence_attached(capa: capa, actor: current_user, document_name: doc_name)
        end
      end
      if attachment.attachable_type == "CapaAction" && attachment.attachable_id.present?
        action = CapaAction.find_by(id: attachment.attachable_id)
        if action&.capa
          doc_name = @upload.display_name.presence || @upload.filename
          NotificationService.notify_capa_evidence_attached(capa: action.capa, actor: current_user, document_name: doc_name)
          NotificationService.notify_auditors_capa_evidence_attached(capa: action.capa, capa_action: action, actor: current_user, document_name: doc_name)
        end
      end
    end

    respond_to do |format|
      if created_count > 0 && errors.empty?
        format.json { render json: {
          success: true,
          message: t("items_linked_successfully", count: created_count),
          created_count: created_count
        }, status: :created }
      elsif created_count > 0
        format.json { render json: {
          success: true,
          message: t("items_partially_linked", count: created_count),
          created_count: created_count,
          errors: errors
        }, status: :ok }
      else
        format.json { render json: {
          success: false,
          message: t("link_items_failed"),
          errors: errors
        }, status: :unprocessable_entity }
      end
    end
  rescue ActiveRecord::RecordNotFound
    respond_to do |format|
      format.json { render json: { error: t("upload_not_found") }, status: :not_found }
    end
  end

  def destroy
    @attachment = EvidenceAttachment.find(params[:id])
    upload = @attachment.upload

    # Ensure current user can access this attachment (upload visible + attachable in company)
    unless attachment_accessible_to_current_user?(@attachment)
      respond_to do |format|
        format.html { redirect_to library_path, alert: t("attachment_not_found"), status: :forbidden }
        format.json { render json: { error: t("attachment_not_found") }, status: :forbidden }
      end
      return
    end

    attachment_id = @attachment.id
    folder_id = upload.folder_id || "all"

    # Store attachment info before destruction for audit log
    attachable_type = @attachment.attachable_type
    attachable_id = @attachment.attachable_id
    attachable_name = @attachment.attachable_name rescue "Unknown"

    if @attachment.destroy
      # Log audit action
      company = upload.company || extract_company_from_attachable(attachable_type, attachable_id) || current_company
      if company && current_user
        AuditLogService.log_action(
          actor_user: current_user,
          company: company,
          action: "UNLINK_DOCUMENT_FROM_#{attachable_type.upcase}",
          entity_type: attachable_type.downcase,
          entity_id: attachable_id,
          payload: {
            upload_id: upload.id,
            upload_name: upload.display_name,
            upload_filename: upload.filename,
            attachable_type: attachable_type,
            attachable_id: attachable_id,
            attachable_name: attachable_name
          }
        )
      end

      respond_to do |format|
        format.html { redirect_to folder_uploads_upload_path(folder_id: folder_id, id: upload.id), notice: t("attachment_unlinked_successfully") }
        format.json { render json: { success: true, message: t("attachment_unlinked_successfully"), attachment_id: attachment_id } }
      end
    else
      respond_to do |format|
        format.html { redirect_to folder_uploads_upload_path(folder_id: folder_id, id: upload.id), alert: t("attachment_unlink_failed") }
        format.json { render json: { success: false, message: t("attachment_unlink_failed") }, status: :unprocessable_entity }
      end
    end
  rescue ActiveRecord::RecordNotFound
    respond_to do |format|
      format.html { redirect_to library_path, alert: t("attachment_not_found") }
      format.json { render json: { error: t("attachment_not_found") }, status: :not_found }
    end
  end

  private

  # True if the attachable belongs to current user's company and user has permission to link.
  # Capa: only Auditor (for their CAPAs) and QM/Admin can attach at CAPA level; Contributor must use CapaAction.
  # CapaAction: only assignees of that action or QM/Admin can attach (comment/upload per action).
  def attachable_accessible_to_current_company?(attachable_type, attachable_id)
    return true if current_user&.super_admin? || current_user&.delegated_admin?
    return false if current_company.blank?

    cu = current_user&.company_user
    return false unless cu

    case attachable_type.to_s
    when "Capa"
      capa = Capa.find_by(id: attachable_id)
      return false unless capa&.company_id == current_company.id
      # Contributor can only add via CapaAction; at CAPA level only Auditor (their CAPAs) and QM/Admin
      return true if cu.has_admin_privileges?
      return false if cu.company_contributor?
      return true if cu.company_auditor? && (capa.capa_assignments.exists?(company_user_id: cu.id) || capa.created_by_id == current_user.id)
      false
    when "CapaAction"
      action = CapaAction.joins(:capa).find_by(id: attachable_id, capas: { company_id: current_company.id })
      return false unless action
      # Only assignees of this action or QM/Admin can attach (comment/upload for that action)
      cu.has_admin_privileges? || action.capa_action_assignments.exists?(company_user_id: cu.id)
    when "Risk", "Vendor", "CustomerCommitment"
      # Governance evidence follows the same rule as the record itself: it must
      # belong to this company, and the role must be allowed to manage it.
      model = attachable_type.to_s.constantize
      record = model.find_by(id: attachable_id, company_id: current_company.id)
      return false unless record

      cu.has_admin_privileges? || cu.company_quality_manager? ||
        (attachable_type.to_s == "Risk" && current_user.can_manage_risks?) ||
        (attachable_type.to_s == "Vendor" && current_user.can_manage_vendors?) ||
        (attachable_type.to_s == "CustomerCommitment" && current_user.can_manage_commitments?)
    when "Standard"
      CompanyStandard.exists?(standard_id: attachable_id, company_id: current_company.id)
    when "Clause"
      clause = Clause.find_by(id: attachable_id)
      standard_id = clause&.standard_version&.standard_id
      standard_id.present? && CompanyStandard.exists?(standard_id: standard_id, company_id: current_company.id)
    when "ChecklistItem"
      item = ChecklistItem.find_by(id: attachable_id)
      clause = item&.clause
      standard_id = clause&.standard_version&.standard_id
      standard_id.present? && CompanyStandard.exists?(standard_id: standard_id, company_id: current_company.id)
    else
      false
    end
  end

  # True if current user is allowed to unlink this evidence attachment (upload visible + attachable in company)
  def attachment_accessible_to_current_user?(attachment)
    return true if current_user&.super_admin? || current_user&.delegated_admin?
    return false unless attachment.upload.visible_to_user?(current_user)
    attachable_accessible_to_current_company?(attachment.attachable_type, attachment.attachable_id)
  end

  def extract_company_from_attachable(attachable_type, attachable_id)
    return nil unless attachable_type && attachable_id

    case attachable_type.to_s
    when "Capa"
      capa = Capa.find_by(id: attachable_id)
      capa&.company
    when "CapaAction"
      action = CapaAction.find_by(id: attachable_id)
      action&.capa&.company
    when "Clause"
      clause = Clause.find_by(id: attachable_id)
      clause&.standard_version&.standard&.company_standards&.first&.company
    when "ChecklistItem"
      checklist_item = ChecklistItem.find_by(id: attachable_id)
      clause = checklist_item&.clause
      clause&.standard_version&.standard&.company_standards&.first&.company
    when "Standard"
      standard = Standard.find_by(id: attachable_id)
      # Standards don't have direct company, but we can get from company_standards
      standard&.company_standards&.first&.company
    else
      nil
    end
  end
end
