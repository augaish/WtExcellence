class AddCreatedByIdToCapaActions < ActiveRecord::Migration[8.0]
  def change
    add_column :capa_actions, :created_by_id, :uuid, null: true
    add_index  :capa_actions, :created_by_id, name: "index_capa_actions_on_created_by_id"
    add_foreign_key :capa_actions, :users, column: :created_by_id
  end
end
