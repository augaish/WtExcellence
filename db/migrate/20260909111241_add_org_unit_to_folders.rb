class AddOrgUnitToFolders < ActiveRecord::Migration[8.0]
  def change
    add_column :folders, :org_unit_id, :uuid
    add_index :folders, :org_unit_id, unique: true
    add_foreign_key :folders, :org_units, on_delete: :nullify
  end
end
