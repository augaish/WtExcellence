class CompanyModule < ApplicationRecord
  belongs_to :company

  validates :module_key,
    presence: true,
    inclusion: { in: ->(_record) { Company.module_keys } },
    uniqueness: { scope: :company_id }
end
