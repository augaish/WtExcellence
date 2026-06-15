class UpdateToolClauseSubcheckpointAssignmentsUniquenessConstraint < ActiveRecord::Migration[8.0]
  def up
    # Remove the old uniqueness constraint that doesn't include company_id
    if index_exists?(:tool_clause_subcheckpoint_assignments, 
                     [:tool_clause_id, :user_id, :tool_subcheckpoint_id],
                     name: "index_tool_clause_subcheckpoint_assignments_unique")
      remove_index :tool_clause_subcheckpoint_assignments, 
                   name: "index_tool_clause_subcheckpoint_assignments_unique"
    end

    # Add new uniqueness constraint that includes company_id
    # This ensures assignments are unique per company, preventing cross-company data leaks
    unless index_exists?(:tool_clause_subcheckpoint_assignments,
                         [:tool_clause_id, :user_id, :tool_subcheckpoint_id, :company_id],
                         name: "index_tool_clause_subcheckpoint_assignments_unique_with_company")
      add_index :tool_clause_subcheckpoint_assignments,
                [:tool_clause_id, :user_id, :tool_subcheckpoint_id, :company_id],
                unique: true,
                name: "index_tool_clause_subcheckpoint_assignments_unique_with_company"
    end
  end

  def down
    # Remove the new constraint
    if index_exists?(:tool_clause_subcheckpoint_assignments,
                     [:tool_clause_id, :user_id, :tool_subcheckpoint_id, :company_id],
                     name: "index_tool_clause_subcheckpoint_assignments_unique_with_company")
      remove_index :tool_clause_subcheckpoint_assignments,
                   name: "index_tool_clause_subcheckpoint_assignments_unique_with_company"
    end

    # Restore the old constraint (without company_id)
    unless index_exists?(:tool_clause_subcheckpoint_assignments,
                         [:tool_clause_id, :user_id, :tool_subcheckpoint_id],
                         name: "index_tool_clause_subcheckpoint_assignments_unique")
      add_index :tool_clause_subcheckpoint_assignments,
                [:tool_clause_id, :user_id, :tool_subcheckpoint_id],
                unique: true,
                name: "index_tool_clause_subcheckpoint_assignments_unique"
    end
  end
end
