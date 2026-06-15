class CreateChecklistItems < ActiveRecord::Migration[8.0]
  def change
    create_table :checklist_items, id: :uuid do |t|
      t.references :clause, null: false, foreign_key: true, type: :uuid
      t.string :item_type, null: false, default: 'requirement', limit: 20
      t.string :code, limit: 100
      t.integer :sort_order, null: false, default: 0
      t.string :stable_key, limit: 200

      t.timestamps
    end

    add_index :checklist_items, [ :clause_id, :sort_order ]
    add_index :checklist_items, [ :clause_id, :code ]
    add_index :checklist_items, :stable_key
  end
end
