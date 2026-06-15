class CreateToolClauseSubcheckpointAssignments < ActiveRecord::Migration[8.0]
  def change
    create_table :tool_clause_subcheckpoint_assignments, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :tool_clause_id, null: false
      t.uuid :user_id, null: false
      t.bigint :tool_subcheckpoint_id, null: false
      t.string :status
      t.decimal :score
      t.text :summary

      t.timestamps
    end

    add_index :tool_clause_subcheckpoint_assignments, [:tool_clause_id, :user_id, :tool_subcheckpoint_id], 
              unique: true, 
              name: "index_tool_clause_subcheckpoint_assignments_unique"
    add_index :tool_clause_subcheckpoint_assignments, :tool_clause_id
    add_index :tool_clause_subcheckpoint_assignments, :user_id
    add_index :tool_clause_subcheckpoint_assignments, :tool_subcheckpoint_id

    add_foreign_key :tool_clause_subcheckpoint_assignments, :tool_clauses, column: :tool_clause_id
    add_foreign_key :tool_clause_subcheckpoint_assignments, :users, column: :user_id
    add_foreign_key :tool_clause_subcheckpoint_assignments, :tool_subcheckpoints, column: :tool_subcheckpoint_id
  end
end


