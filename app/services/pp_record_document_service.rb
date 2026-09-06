# Files a document uploaded from a P&P record into the Library, so the record
# and the Library never hold two copies of the truth: the Library owns the file,
# the record links to it (exactly how Standards and CAPA already work).
#
# Uploads land in "P&P" > "<Record type>" so the Library stays organised without
# the user having to pick a folder.
class PpRecordDocumentService
  ROOT_FOLDER_NAME = "P&P".freeze
  FOLDER_COLOR = "#5C3984".freeze

  def self.upload_into_library(file:, record:, company:, user:)
    new(file: file, record: record, company: company, user: user).call
  end

  # Finds (or creates) the "P&P" > "<Record type>" folder for a company.
  def self.folder_for(record_type:, company:)
    new(file: nil, record: nil, company: company, user: nil).folder_for(record_type)
  end

  def initialize(file:, record:, company:, user:)
    @file = file
    @record = record
    @company = company
    @user = user
  end

  def call
    return nil if @file.blank? || @user.nil?

    upload = Upload.new(
      company_id: @company.id,
      folder: folder_for(@record&.record_type),
      filename: @file.original_filename,
      name: @file.original_filename,
      mime_type: @file.content_type.presence || "application/octet-stream",
      size_bytes: @file.size,
      uploaded_by: @user.id,
      visibility: "private"
    )
    upload.file.attach(@file)
    upload.save!
    upload
  end

  def folder_for(record_type)
    root = @company.folders.find_or_create_by!(name: ROOT_FOLDER_NAME, parent_id: nil) do |f|
      f.color = FOLDER_COLOR
      f.created_by = @user&.id
    end

    return root if record_type.blank?

    label = I18n.t("pp_records.types.#{record_type}", locale: :en, default: record_type.to_s.humanize)
    @company.folders.find_or_create_by!(name: label, parent_id: root.id) do |f|
      f.color = FOLDER_COLOR
      f.created_by = @user&.id
    end
  end
end
