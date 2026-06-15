class AddNameAndNotesToUploads < ActiveRecord::Migration[8.0]
  def change
    add_column :uploads, :name, :string, limit: 255
    add_column :uploads, :notes, :text
  end
end
