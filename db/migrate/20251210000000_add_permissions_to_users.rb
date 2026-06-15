class AddPermissionsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :permissions, :jsonb, default: [], null: false
    add_index :users, :permissions, using: :gin
  end
end

