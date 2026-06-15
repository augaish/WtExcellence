class CreateFolders < ActiveRecord::Migration[8.0]
  def change
    create_table :folders, id: :uuid do |t|
      t.string :name, null: false, limit: 255
      t.text :description
      t.uuid :created_by
      t.integer :files_count, default: 0, null: false

      t.timestamps
    end

    add_index :folders, :created_by
  end
end
