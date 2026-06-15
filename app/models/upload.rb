class Upload < ApplicationRecord
  # Active Storage attachment
  has_one_attached :file

  # Validations
  validates :filename, presence: true, length: { maximum: 255 }
  validates :name, length: { maximum: 255 }, allow_blank: true
  validates :mime_type, presence: true
  validates :size_bytes, presence: true, numericality: { greater_than: 0 }
  validates :uploaded_by, presence: true
  validates :file, presence: true
  validates :visibility, presence: true, inclusion: { in: %w[private public] }
  # TODO: Make company_id required after backfilling existing records
  # validates :company_id, presence: true

  # Associations
  belongs_to :company, optional: true
  belongs_to :uploader, class_name: "User", foreign_key: "uploaded_by", optional: true
  has_many :ingestion_jobs, foreign_key: "input_pdf_id", dependent: :destroy
  belongs_to :folder, optional: true
  has_many :evidence_attachments, dependent: :destroy
  has_many :linked_standards, through: :evidence_attachments, source: :attachable, source_type: "Standard"
  has_many :linked_clauses, through: :evidence_attachments, source: :attachable, source_type: "Clause"
  has_many :linked_checklist_items, through: :evidence_attachments, source: :attachable, source_type: "ChecklistItem"

  # Scopes
  scope :pdf_files, -> { where(mime_type: "application/pdf") }
  scope :recent, -> { order(created_at: :desc) }
  scope :for_company, ->(company_id) { where(company_id: company_id) }
  scope :public_uploads, -> { where(visibility: "public") }
  scope :private_uploads, -> { where(visibility: "private") }

  # Scope to get uploads visible to a specific user
  scope :visible_to_user, ->(user) {
    if user&.super_admin? || user&.delegated_admin?
      # Super admins and delegated admins can see all uploads
      all
    else
      company = user&.company
      if company
        company_user = user&.company_user
        is_company_admin = company_user&.has_admin_privileges? || false

        # Public uploads OR private uploads where user is the uploader OR user is company admin
        if is_company_admin
          where(
            "(visibility = 'public') OR (visibility = 'private' AND (uploaded_by = ? OR company_id = ?))",
            user.id,
            company.id
          )
        else
          where(
            "(visibility = 'public') OR (visibility = 'private' AND uploaded_by = ?)",
            user.id
          )
        end
      else
        # User has no company, can only see public uploads they uploaded
        where("visibility = 'public' OR (visibility = 'private' AND uploaded_by = ?)", user.id)
      end
    end
  }

  # Callbacks
  before_validation :set_file_metadata, if: -> { file.attached? }
  after_save :update_folder_files_count, if: -> { saved_change_to_folder_id? }
  after_destroy :update_folder_files_count

  # Instance methods
  def file_size_mb
    return 0 unless file.attached?
    (file.byte_size / 1024.0 / 1024.0).round(2)
  end

  def pdf?
    mime_type == "application/pdf"
  end

  def display_name
    name.presence || filename.presence || "Unknown file"
  end

  def file_url(expires_in: 1.hour, disposition: "attachment")
    return nil unless file.attached?

    file.blob.service.url(
      file.blob.key,
      expires_in: expires_in,
      filename: file.blob.filename,
      content_type: nil,
      disposition: disposition
    )
  end

  def file_exists?
    file.attached? && file.blob.persisted?
  end

  def public?
    visibility == "public"
  end

  def private?
    visibility == "private"
  end

  # Check if a user can see this upload
  def visible_to_user?(user)
    return true if user.nil? # Allow nil check for safety
    return true if user.super_admin? || user.delegated_admin? # Super admins and delegated admins can see all

    return true if public? # Public uploads are visible to everyone

    # Private uploads: only visible to uploader or company admins
    return true if uploaded_by == user.id

    company = user.company
    return false unless company && company_id == company.id

    company_user = user.company_user
    company_user&.has_admin_privileges? || false
  end

  # Class methods
  def self.create_from_uploaded_file(uploaded_file, uploaded_by_id, company_id: nil, visibility: "public")
    # Create new upload instance
    upload = new(
      uploaded_by: uploaded_by_id,
      filename: uploaded_file.original_filename,
      mime_type: uploaded_file.content_type,
      size_bytes: uploaded_file.size,
      company_id: company_id,
      visibility: visibility
    )

    # Attach the file BEFORE saving (this is required for validation)
    # For ActionDispatch::Http::UploadedFile, we can attach it directly
    upload.file.attach(uploaded_file)

    # Now save the record (validations will pass since file is attached)
    upload.save!

    upload
  rescue => e
    Rails.logger.error "Upload error: #{e.message}"
    Rails.logger.error e.backtrace.first(5)
    raise e
  end

  private

  def set_file_metadata
    return unless file.attached?

    self.filename ||= file.filename.to_s
    self.mime_type ||= file.content_type
    self.size_bytes ||= file.byte_size
  end

  def update_folder_files_count
    # Update old folder if folder_id changed
    if folder_id_before_last_save.present?
      old_folder = Folder.find_by(id: folder_id_before_last_save)
      if old_folder
        old_folder.update_files_count!
        # Update all parent folders recursively
        update_parent_folders_count(old_folder)
      end
    end

    # Update new folder
    if folder
      folder.update_files_count!
      # Update all parent folders recursively
      update_parent_folders_count(folder)
    end
  end

  def update_parent_folders_count(folder)
    return unless folder.parent

    folder.parent.update_files_count!
    update_parent_folders_count(folder.parent)
  end
end
