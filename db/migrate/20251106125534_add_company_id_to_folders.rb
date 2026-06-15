class AddCompanyIdToFolders < ActiveRecord::Migration[8.0]
  def change
    add_column :folders, :company_id, :uuid, null: true
    add_index :folders, :company_id
    add_foreign_key :folders, :companies, type: :uuid
  end
end
