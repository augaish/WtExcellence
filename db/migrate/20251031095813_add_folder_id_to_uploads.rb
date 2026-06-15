class AddFolderIdToUploads < ActiveRecord::Migration[8.0]
  def change
    add_column :uploads, :folder_id, :uuid, null: true
    add_index :uploads, :folder_id
    add_foreign_key :uploads, :folders
  end
end
