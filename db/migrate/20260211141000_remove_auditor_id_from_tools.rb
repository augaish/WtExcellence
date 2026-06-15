class RemoveAuditorIdFromTools < ActiveRecord::Migration[7.1]
  def change
    remove_foreign_key :tools, column: :auditor_id, if_exists: true
    remove_column :tools, :auditor_id, :uuid
  end
end

