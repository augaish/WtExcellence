class RemoveUnusedColumnsFromUploads < ActiveRecord::Migration[8.0]
  def change
    # Remove columns that are no longer needed with Active Storage
    remove_column :uploads, :storage_path, :string
  end
end
