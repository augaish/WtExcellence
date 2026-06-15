class CompanyClauseInstance < ApplicationRecord
  # Validations
  validates :company_standard_id, presence: true
  validates :clause_id, presence: true
  validates :version_id, presence: true
  validates :company_standard_id, uniqueness: { scope: :clause_id }

  # Associations
  belongs_to :company_standard
  belongs_to :clause
  belongs_to :version, class_name: "StandardVersion", foreign_key: "version_id"

  has_many :company_checklist_item_instances, dependent: :destroy

  # Scopes
  scope :for_company_standard, ->(company_standard_id) { where(company_standard_id: company_standard_id) }
  scope :for_version, ->(version_id) { where(version_id: version_id) }

  # Instance methods
  # Get the clause code (denormalized for performance)
  def clause_code
    super || clause.code
  end
end
