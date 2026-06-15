class AddCachedComplianceToCompanyStandards < ActiveRecord::Migration[8.0]
  def change
    add_column :company_standards, :cached_compliance_percentage, :decimal, precision: 5, scale: 2
    add_column :company_standards, :cached_compliance_at, :datetime
    add_index :company_standards, :cached_compliance_percentage
  end
end
