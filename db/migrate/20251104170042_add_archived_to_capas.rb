class AddArchivedToCapas < ActiveRecord::Migration[8.0]
  def change
    add_column :capas, :archived, :boolean, default: false, null: false
    add_index :capas, :archived
  end
end
