class CreateToolClauses < ActiveRecord::Migration[8.0]
  def change
    create_table :tool_clauses, id: :uuid do |t|
      t.references :tool, null: false, foreign_key: true
      t.references :clause, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end

    add_index :tool_clauses, [ :tool_id, :clause_id ], unique: true
  end
end
