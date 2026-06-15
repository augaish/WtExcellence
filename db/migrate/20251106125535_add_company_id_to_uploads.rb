class AddCompanyIdToUploads < ActiveRecord::Migration[8.0]
  def change
    add_column :uploads, :company_id, :uuid, null: true
    add_index :uploads, :company_id
    add_foreign_key :uploads, :companies, type: :uuid
  end
end
