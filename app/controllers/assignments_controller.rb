# Assignments are represented by Assessment (container). The join table
# assessment_users only links users to the container (who is assigned)
# and holds evidence attachments per user. Evaluation, status, summary, and comments live on the container.
class AssignmentsController < Dashboard::BaseController
  before_action :authenticate_user!
  before_action :block_platform_admins
  before_action :set_assignment

  def show
    # /assignments/:id is a legacy URL — redirect to the assessment page.
    clause = @assignment_container.tool_clause&.clause
    if clause
      redirect_to clause_assessment_path(clause)
    else
      redirect_to dashboard_path, alert: "Assessment not found"
    end
  end

  def link_documents
    return if prevent_viewer_action

    unless @assignment_container.assessment_users.exists?(user_id: current_user.id) ||
           current_user&.company_user&.has_admin_privileges?
      notification_html = render_to_string(partial: "shared/notification", locals: { message: "You don't have permission to link documents to this assessment", type: :error, animated: true }, formats: [ :html ])
      render json: { success: false, message: "Permission denied", notification_html: notification_html }, status: :forbidden and return
    end

    company = current_company
    unless company
      notification_html = render_to_string(partial: "shared/notification", locals: { message: "Company not found", type: :error, animated: true }, formats: [ :html ])
      render json: { success: false, message: "Company not found", notification_html: notification_html }, status: :forbidden and return
    end

    upload_ids = params[:upload_ids] || []
    checklist_item_id = params[:checklist_item_id].presence
    created_count = 0
    errors = []
    linked_documents = []

    # When a checklist_item_id is provided, attach evidence at the checkpoint
    # (ChecklistItem) level. Otherwise fall back to the assessment-level
    # attachment for older callers.
    target_checklist_item = nil
    if checklist_item_id
      target_checklist_item = ChecklistItem.joins(:clause)
                                           .find_by(id: checklist_item_id, clauses: { id: @assignment_container.tool_clause&.clause_id })
      unless target_checklist_item
        notification_html = render_to_string(partial: "shared/notification", locals: { message: "Checkpoint not found for this assessment", type: :error, animated: true }, formats: [ :html ])
        render json: { success: false, message: "Checkpoint not found", notification_html: notification_html }, status: :unprocessable_entity and return
      end
    end

    upload_ids.each do |upload_id|
      unless upload_id.present?
        errors << "Upload ID is required"
        next
      end

      upload = Upload.find_by(id: upload_id)
      unless upload
        errors << "Document #{upload_id} not found"
        next
      end

      unless upload.company_id == @assignment_container.company_id
        errors << "Document #{upload.display_name} does not belong to this assignment's company"
        next
      end

      if target_checklist_item
        existing = EvidenceAttachment.find_by(
          attachable_type: "ChecklistItem",
          attachable_id: target_checklist_item.id,
          upload_id: upload_id
        )
        next if existing

        evidence_attachment = EvidenceAttachment.new(
          attachable: target_checklist_item,
          upload: upload,
          attached_by: current_user.id
        )
      else
        existing = EvidenceAttachment.find_by(
          attachable_type: "Assessment",
          attachable_id: @assignment_container.id,
          upload_id: upload_id
        )
        next if existing

        evidence_attachment = EvidenceAttachment.new(
          attachable: @assignment_container,
          upload: upload,
          attached_by: current_user.id
        )
      end

      if evidence_attachment.save
        created_count += 1
        linked_documents << upload
      else
        errors << evidence_attachment.errors.full_messages.join(", ")
      end
    end

    # Update assessment status to 'in_drafts' when documents were linked
    if created_count > 0 && @assignment_container.status == "not_started"
      @assignment_container.update!(status: "in_drafts")
    end

    if created_count > 0
      AuditLogService.log_action(
        actor_user: current_user,
        company: company,
        action: "LINK_DOCUMENTS_TO_ASSIGNMENT",
        entity_type: "assessment",
        entity_id: @assignment_container.id,
        payload: {
          document_count: created_count,
          document_ids: linked_documents.map(&:id),
          document_names: linked_documents.map(&:display_name),
          tool_clause_id: @assignment_container.tool_clause_id,
          clause_id: @assignment_container.tool_clause&.clause_id
        }
      )
    end

    respond_to do |format|
      if created_count > 0 && errors.empty?
        notification_html = render_to_string(partial: "shared/notification", locals: { message: "#{created_count} document(s) linked successfully", type: :success, animated: true }, formats: [ :html ])
        format.json { render json: {
          success: true,
          message: "#{created_count} document(s) linked successfully",
          notification_html: notification_html,
          documents: linked_documents.map { |doc| {
            id: doc.id,
            display_name: doc.display_name,
            name: doc.name,
            mime_type: doc.mime_type,
            created_at: doc.created_at,
            notes: doc.notes
          } }
        }, status: :created }
      elsif created_count > 0
        notification_html = render_to_string(partial: "shared/notification", locals: { message: "#{created_count} document(s) linked, but some errors occurred", type: :warning, animated: true }, formats: [ :html ])
        format.json { render json: {
          success: true,
          message: "#{created_count} document(s) linked, but some errors occurred",
          notification_html: notification_html,
          documents: linked_documents.map { |doc| {
            id: doc.id,
            display_name: doc.display_name,
            name: doc.name,
            mime_type: doc.mime_type,
            created_at: doc.created_at,
            notes: doc.notes,
            file_attached: doc.file.attached?,
            file_url: doc.file.attached? ? helpers.signed_file_url(doc.file, disposition: "attachment") : nil
          } },
          errors: errors
        }, status: :ok }
      else
        notification_html = render_to_string(partial: "shared/notification", locals: { message: "Failed to link documents: #{errors.join(', ')}", type: :error, animated: true }, formats: [ :html ])
        format.json { render json: {
          success: false,
          message: "Failed to link documents",
          notification_html: notification_html,
          errors: errors
        }, status: :unprocessable_entity }
      end
    end
  end

  def unlink_document
    unless @assignment_container.assessment_users.exists?(user_id: current_user.id) ||
           current_user&.company_user&.has_admin_privileges?
      notification_html = render_to_string(partial: "shared/notification", locals: { message: "You don't have permission to unlink documents from this assignment", type: :error, animated: true }, formats: [ :html ])
      render json: { success: false, message: "Permission denied", notification_html: notification_html }, status: :forbidden and return
    end
    upload_id = params[:upload_id]

    is_contributor = @assignment_container.assessment_users.exists?(user_id: current_user.id) &&
      !CompanyUser.find_by(user_id: current_user.id, company_id: @assignment_container.company_id)&.company_auditor?
    assignment_company_user = CompanyUser.find_by(user_id: current_user.id, company_id: @assignment_container.company_id)
    is_admin = assignment_company_user&.has_admin_privileges?

    unless is_contributor || is_admin
      notification_html = render_to_string(partial: "shared/notification", locals: { message: "You don't have permission to unlink documents from this assignment", type: :error, animated: true }, formats: [ :html ])
      render json: { success: false, message: "Permission denied", notification_html: notification_html }, status: :forbidden and return
    end

    company = current_company
    unless company
      notification_html = render_to_string(partial: "shared/notification", locals: { message: "Company not found", type: :error, animated: true }, formats: [ :html ])
      render json: { success: false, message: "Company not found", notification_html: notification_html }, status: :forbidden and return
    end

    checklist_item_id = params[:checklist_item_id].presence

    evidence_attachment =
      if checklist_item_id
        target_checklist_item = ChecklistItem.joins(:clause)
                                             .find_by(id: checklist_item_id, clauses: { id: @assignment_container.tool_clause&.clause_id })
        unless target_checklist_item
          notification_html = render_to_string(partial: "shared/notification", locals: { message: "Checkpoint not found for this assessment", type: :error, animated: true }, formats: [ :html ])
          render json: { success: false, message: "Checkpoint not found", notification_html: notification_html }, status: :not_found and return
        end

        EvidenceAttachment.find_by(
          attachable_type: "ChecklistItem",
          attachable_id: target_checklist_item.id,
          upload_id: upload_id
        )
      else
        EvidenceAttachment.find_by(
          attachable_type: "Assessment",
          attachable_id: @assignment_container.id,
          upload_id: upload_id
        )
      end

    unless evidence_attachment
      notification_html = render_to_string(partial: "shared/notification", locals: { message: "Document not found or not linked to this assignment", type: :error, animated: true }, formats: [ :html ])
      render json: { success: false, message: "Document not found", notification_html: notification_html }, status: :not_found and return
    end

    unless evidence_attachment.upload.company_id == @assignment_container.company_id
      notification_html = render_to_string(partial: "shared/notification", locals: { message: "Document does not belong to your company", type: :error, animated: true }, formats: [ :html ])
      render json: { success: false, message: "Permission denied", notification_html: notification_html }, status: :forbidden and return
    end

    if evidence_attachment.destroy
      AuditLogService.log_action(
        actor_user: current_user,
        company: company,
        action: "UNLINK_DOCUMENT_FROM_ASSIGNMENT",
        entity_type: "assessment",
        entity_id: @assignment_container.id,
        payload: {
          upload_id: upload_id,
          upload_name: evidence_attachment.upload&.display_name,
          tool_clause_id: @assignment_container.tool_clause_id,
          clause_id: @assignment_container.tool_clause&.clause_id,
          checklist_item_id: checklist_item_id
        }
      )

      notification_html = render_to_string(partial: "shared/notification", locals: { message: "Document unlinked successfully", type: :success, animated: true }, formats: [ :html ])
      render json: { success: true, message: "Document unlinked successfully", notification_html: notification_html }, status: :ok
    else
      notification_html = render_to_string(partial: "shared/notification", locals: { message: "Failed to unlink document", type: :error, animated: true }, formats: [ :html ])
      render json: { success: false, message: "Failed to unlink document", notification_html: notification_html }, status: :unprocessable_entity
    end
  end

  private

  def set_assignment
    # params[:id] is now an Assessment ID
    @assignment_container = Assessment.find(params[:id])

    # Verify assessment belongs to current company
    company = current_company
    unless company && @assignment_container.company_id == company.id
      redirect_back(fallback_location: dashboard_path, alert: "You don't have access to this assessment")
      return
    end
  end

  def block_platform_admins
    return unless current_user&.platform_admin?
    redirect_back(fallback_location: dashboard_path, alert: "Assessments are only available for company users")
  end
end
