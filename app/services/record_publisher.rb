# The last step of every flow. Publishing moves the record to its terminal
# stage, prints the document to PDF into the owning unit's Library folder,
# and tells everyone in the company. A glossary term also becomes a company
# glossary entry so documents can pull its definition.
#
# Either door leads here: the P&P Manager confirming a publisher's link, or
# the "publish in the system only" choice.
class RecordPublisher
  def self.publish!(record, by:, company:)
    new(record, by: by, company: company).publish!
  end

  def initialize(record, by:, company:)
    @record = record
    @user = by
    @company = company
  end

  def publish!
    PpStageTransitionService.new(record: @record, user: @user, company: @company).publish!
    @record.update!(published_at: Time.current)

    file_pdf
    refresh_glossary_term if @record.glossary?
    DocumenterNotifier.notify_published(@record)
    @record
  end

  private

  def file_pdf
    renderer = RecordPdfRenderer.new(@record, locale: document_locale)
    pdf = renderer.render
    return if pdf.nil?

    upload = Upload.new(
      company_id: @company.id,
      folder: target_folder,
      filename: renderer.filename,
      name: renderer.filename,
      mime_type: "application/pdf",
      size_bytes: pdf.bytesize,
      uploaded_by: @user&.id,
      visibility: "public"
    )
    upload.file.attach(io: StringIO.new(pdf), filename: renderer.filename, content_type: "application/pdf")
    upload.save!
    @record.update!(published_pdf_upload: upload)
  end

  # Arabic when the document has an Arabic title, otherwise English.
  def document_locale
    @record.title_ar.present? ? :ar : :en
  end

  # The owning unit's folder, built from the org structure if it is not there
  # yet; the P&P folder when the record has no owning unit.
  def target_folder
    unit = @record.owner_org_unit
    if unit
      folder = Folder.find_by(org_unit_id: unit.id)
      if folder.nil?
        OrgLibraryBuilder.build(@company, user: @user)
        folder = Folder.find_by(org_unit_id: unit.id)
      end
      return folder if folder
    end

    PpRecordDocumentService.folder_for(record_type: @record.record_type, company: @company)
  end

  def refresh_glossary_term
    term = @company.glossary_terms.find_or_initialize_by(term_en: @record.title_en.presence, term_ar: @record.title_ar.presence)
    term.definition_en = @record.description if @record.title_en.present? || term.definition_en.blank?
    term.definition_ar = @record.description if @record.title_ar.present?
    term.active = true
    term.save!
  end
end
