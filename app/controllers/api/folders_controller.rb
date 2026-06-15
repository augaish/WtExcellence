class Api::FoldersController < Dashboard::BaseController
  def index
    parent_id = params[:parent_id].presence

    # Filter by company for non-platform-admin users
    if current_user&.platform_admin?
      folders = Folder.all
    else
      company = current_company
      if company
        folders = Folder.where(company_id: company.id).where.not(company_id: nil)
      else
        folders = Folder.none
      end
    end

    # Filter by parent if specified (for subfolders)
    if parent_id.present?
      folders = folders.where(parent_id: parent_id)
    else
      # If no parent_id, return root folders only
      folders = folders.root_folders
    end

    # Format folders for JSON response
    folders_data = folders.order(:name).map do |folder|
      {
        id: folder.id,
        name: folder.name,
        description: folder.description,
        file_count: folder.file_count,
        color: folder.color || "#5C3984",
        parent_id: folder.parent_id,
        updated_at: folder.updated_at.strftime("%b %d, %Y"),
        updated_at_iso: folder.updated_at.iso8601
      }
    end

    render json: {
      folders: folders_data
    }
  end

  def show
    folder = Folder.find_by(id: params[:id])

    unless folder
      render json: { error: "Folder not found" }, status: :not_found
      return
    end

    # Check access
    unless current_user&.platform_admin?
      company = current_company
      if company.nil? || folder.company_id.nil? || folder.company_id != company.id
        render json: { error: "Access denied" }, status: :forbidden
        return
      end
    end

    render json: {
      folder: {
        id: folder.id,
        name: folder.name,
        description: folder.description,
        file_count: folder.file_count,
        color: folder.color || "#5C3984",
        parent_id: folder.parent_id,
        updated_at: folder.updated_at.strftime("%b %d, %Y"),
        updated_at_iso: folder.updated_at.iso8601
      },
      subfolders: folder.children.order(:name).map do |subfolder|
        {
          id: subfolder.id,
          name: subfolder.name,
          description: subfolder.description,
          file_count: subfolder.file_count,
          color: subfolder.color || "#5C3984",
          parent_id: subfolder.parent_id,
          updated_at: subfolder.updated_at.strftime("%b %d, %Y"),
          updated_at_iso: subfolder.updated_at.iso8601
        }
      end
    }
  end
end
