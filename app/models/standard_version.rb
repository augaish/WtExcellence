class StandardVersion < ApplicationRecord
  # Validations
  validates :standard_id, presence: true
  validates :version_label, presence: true, length: { maximum: 100 }
  validates :status, presence: true, inclusion: { in: %w[draft published archived] }

  # Associations
  belongs_to :standard
  belongs_to :source_pdf, class_name: "Upload", optional: true
  has_many :clauses, dependent: :destroy
  has_many :company_standards, foreign_key: "active_version_id", dependent: :nullify
  has_many :company_standard_version_history_from, class_name: "CompanyStandardVersionHistory", foreign_key: "from_version_id", dependent: :nullify
  has_many :company_standard_version_history_to, class_name: "CompanyStandardVersionHistory", foreign_key: "to_version_id", dependent: :nullify
  has_many :company_clause_instances, foreign_key: "version_id", dependent: :destroy

  # Scopes
  scope :published, -> { where(status: "published") }
  scope :draft, -> { where(status: "draft") }
  scope :archived, -> { where(status: "archived") }
  scope :recent, -> { order(created_at: :desc) }

  # Instance methods
  def published?
    status == "published"
  end

  def draft?
    status == "draft"
  end

  def archived?
    status == "archived"
  end

  def display_name
    "#{standard.code} #{version_label}"
  end

  def root_clauses
    clauses.root_clauses.ordered
  end
end
