class AddParentIdToFolders < ActiveRecord::Migration[8.0]
  def change
    add_reference :folders, :parent, foreign_key: { to_table: :folders }, type: :uuid, null: true, index: true
  end
end
