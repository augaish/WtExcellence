class CompanyStandardVersionHistory < ApplicationRecord
  self.table_name = "company_standard_version_history"

  # Validations
  validates :company_standard_id, presence: true
  validates :to_version_id, presence: true

  # Associations
  belongs_to :company_standard
  belongs_to :from_version, class_name: "StandardVersion", foreign_key: "from_version_id", optional: true
  belongs_to :to_version, class_name: "StandardVersion", foreign_key: "to_version_id"
  belongs_to :changed_by_user, class_name: "User", foreign_key: "changed_by", optional: true

  # Scopes
  scope :recent, -> { order(changed_at: :desc) }
  scope :for_company_standard, ->(company_standard_id) { where(company_standard_id: company_standard_id) }
end
