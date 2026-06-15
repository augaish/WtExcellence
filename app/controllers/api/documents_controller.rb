class Api::DocumentsController < Dashboard::BaseController
  # GET /api/documents (optional: folder_id)
  # Returns documents (uploads) visible to the current user.
  # - Platform admins (super / delegated): all uploads (optionally filtered by folder_id).
  # - Company users: uploads in their company, respecting visibility (public vs private).
  def index
    folder_id = params[:folder_id].presence
    company = current_user&.platform_admin? ? nil : current_company

    # Base scope: apply visibility so private uploads are only shown to uploader or company admins
    uploads = Upload.visible_to_user(current_user).includes(:folder).order(created_at: :desc)

    # Optional folder filter (folder_id is not trusted for cross-company access; company filter below enforces scope)
    uploads = uploads.where(folder_id: folder_id) if folder_id.present?

    # Restrict to current company for non-platform-admin users
    unless current_user&.platform_admin?
      if company
        uploads = uploads.where(company_id: company.id).where.not(company_id: nil)
      else
        uploads = Upload.none
      end
    end

    # Format documents for JSON response
    documents = uploads.map do |upload|
      {
        id: upload.id,
        name: upload.name,
        filename: upload.filename,
        display_name: upload.display_name,
        mime_type: upload.mime_type,
        notes: upload.notes,
        folder_id: upload.folder_id,
        folder_name: upload.folder&.name,
        created_at: upload.created_at.strftime("%b %d, %Y"),
        created_at_iso: upload.created_at.iso8601,
        file_url: upload.file_url
      }
    end

    render json: {
      documents: documents
    }
  end
end
