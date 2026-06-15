class AddCachedPointsToCompanyStandards < ActiveRecord::Migration[8.0]
  def change
    add_column :company_standards, :cached_total_scored_points, :decimal, precision: 10, scale: 2
    add_column :company_standards, :cached_total_allocated_points, :decimal, precision: 10, scale: 2
  end
end
