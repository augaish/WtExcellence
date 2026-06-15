class AddUniqueIndexToClauseIdOnToolClauses < ActiveRecord::Migration[8.0]
  def change
    # Remove the existing non-unique index on clause_id
    remove_index :tool_clauses, :clause_id if index_exists?(:tool_clauses, :clause_id)
    
    # Add a unique index on clause_id to ensure one tool per clause
    add_index :tool_clauses, :clause_id, unique: true
  end
end

