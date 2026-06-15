class AddStatusToUsersAndCompanies < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :status, :string, default: "active"
    add_column :companies, :status, :string, default: "active"

    add_index :users, :status
    add_index :companies, :status
  end
end
