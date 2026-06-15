class AddColorToFolders < ActiveRecord::Migration[8.0]
  def change
    add_column :folders, :color, :string, default: "#5C3984", null: false
  end
end
