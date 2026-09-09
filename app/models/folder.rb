class Folder < ApplicationRecord
  # Validations
  validates :name, presence: true, length: { maximum: 255 }
  validates :color, presence: true, format: { with: /\A#[0-9A-Fa-f]{6}\z/, message: "must be a valid hex color" }
  validate :parent_must_be_same_company
  validate :cannot_be_own_parent
  # TODO: Make company_id required after backfilling existing records
  # validates :company_id, presence: true

  # Associations
  belongs_to :company, optional: true
  belongs_to :creator, class_name: "User", foreign_key: "created_by", optional: true
  belongs_to :parent, class_name: "Folder", optional: true
  # Set when the folder was built from the organization structure, so a rebuild
  # finds and updates the same folder instead of creating a second one.
  belongs_to :org_unit, class_name: "OrgUnit", optional: true
  has_many :children, class_name: "Folder", foreign_key: "parent_id", dependent: :destroy
  has_many :uploads, dependent: :destroy

  # Scopes
  scope :ordered, -> { order(created_at: :desc) }
  scope :recent, -> { order(updated_at: :desc) }
  scope :for_company, ->(company_id) { where(company_id: company_id) }
  scope :root_folders, -> { where(parent_id: nil) }

  # Instance methods
  def file_count
    # Count files directly in this folder plus all files in subfolders
    uploads.count + children.sum(&:file_count)
  end

  def update_files_count!
    update_column(:files_count, uploads.count)
  end

  def full_path
    return name if parent.nil?
    "#{parent.full_path} / #{name}"
  end

  def depth
    return 0 if parent.nil?
    parent.depth + 1
  end

  def ancestors
    return [] if parent.nil?
    [ parent ] + parent.ancestors
  end

  private

  def parent_must_be_same_company
    return unless parent_id.present?
    return unless parent.present?

    if parent.company_id != company_id
      errors.add(:parent_id, "must belong to the same company")
    end
  end

  def cannot_be_own_parent
    return unless parent_id.present?

    if parent_id == id
      errors.add(:parent_id, "cannot be its own parent")
      return
    end

    # Check if this folder is an ancestor of the parent (prevent circular references)
    if parent.present?
      parent_ancestors = parent.ancestors
      if parent_ancestors.include?(self)
        errors.add(:parent_id, "cannot create circular folder structure")
      end
    end
  end
end
