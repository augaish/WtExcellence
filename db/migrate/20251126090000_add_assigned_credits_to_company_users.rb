class AddAssignedCreditsToCompanyUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :company_users, :assigned_credits, :integer, null: false, default: 0
  end
end

