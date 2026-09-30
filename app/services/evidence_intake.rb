# Attaches evidence to a record from both places a person has it: files
# already in the Library (ticked in a list) and files on their own device
# (uploaded here, filed in the Library under the record's module folder).
#
#   EvidenceIntake.attach(assessment, company:, user:, upload_ids: [...], files: [...], folder_name: "Vendors")
class EvidenceIntake
  def self.attach(attachable, company:, user:, upload_ids: [], files: [], folder_name:)
    new(attachable, company: company, user: user, folder_name: folder_name).attach(upload_ids, files)
  end

  def initialize(attachable, company:, user:, folder_name:)
    @attachable = attachable
    @company = company
    @user = user
    @folder_name = folder_name
  end

  def attach(upload_ids, files)
    uploads = Array(upload_ids).compact_blank.filter_map { |id| @company.uploads.find_by(id: id) }
    uploads += Array(files).compact_blank.filter_map { |file| store(file) }
    uploads.uniq.each do |upload|
      next if @attachable.evidence_attachments.exists?(upload_id: upload.id)

      @attachable.evidence_attachments.create!(upload: upload, attached_by: @user.id)
    end
    uploads.size
  end

  private

  def store(file)
    return nil unless file.respond_to?(:original_filename)

    upload = Upload.new(company_id: @company.id, folder: folder, filename: file.original_filename, name: file.original_filename,
      mime_type: file.content_type, size_bytes: file.size, uploaded_by: @user.id, visibility: "public")
    upload.file.attach(io: file, filename: file.original_filename, content_type: file.content_type)
    upload.save ? upload : nil
  end

  def folder
    @folder ||= Folder.find_or_create_by!(company_id: @company.id, name: @folder_name, parent_id: nil) { |f| f.created_by = @user.id }
  end
end
