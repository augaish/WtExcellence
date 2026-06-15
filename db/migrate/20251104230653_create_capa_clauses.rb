class CreateCapaClauses < ActiveRecord::Migration[8.0]
  def change
    create_table :capa_clauses, id: :uuid do |t|
      t.references :capa, null: false, foreign_key: true, type: :uuid
      t.references :clause, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end

    add_index :capa_clauses, [ :capa_id, :clause_id ], unique: true
  end
end
