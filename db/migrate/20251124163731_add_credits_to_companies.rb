class AddCreditsToCompanies < ActiveRecord::Migration[8.0]
  def change
    add_column :companies, :credits, :integer, default: 1000, null: false
  end
end
