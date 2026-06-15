class AddVisibilityToUploads < ActiveRecord::Migration[8.0]
  def change
    add_column :uploads, :visibility, :string, default: 'public', null: false
    add_index :uploads, :visibility
  end
end
