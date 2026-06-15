class CreateClauses < ActiveRecord::Migration[8.0]
  def change
    create_table :clauses, id: :uuid do |t|
      t.references :standard_version, null: false, foreign_key: true, type: :uuid
      t.references :parent, null: true, foreign_key: { to_table: :clauses }, type: :uuid
      t.string :code, null: false, limit: 100
      t.integer :sort_order, null: false, default: 0
      t.string :stable_key, limit: 200

      t.timestamps
    end

    add_index :clauses, [ :standard_version_id, :code ], unique: true
    add_index :clauses, [ :standard_version_id, :parent_id, :sort_order ]
    add_index :clauses, :stable_key
  end
end
