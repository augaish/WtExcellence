class AddOriginToCapas < ActiveRecord::Migration[8.0]
  def change
    add_column :capas, :origin_type, :string
    add_column :capas, :origin_id, :uuid
    add_index :capas, [ :origin_type, :origin_id ]
  end
end
