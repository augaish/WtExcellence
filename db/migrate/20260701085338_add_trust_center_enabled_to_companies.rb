class AddTrustCenterEnabledToCompanies < ActiveRecord::Migration[8.0]
  def change
    add_column :companies, :trust_center_enabled, :boolean, default: false, null: false
  end
end
