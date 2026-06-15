class AddAssignerUserIdToToolClauseSubcheckpointAssignments < ActiveRecord::Migration[8.0]
  def up
    # Check if column already exists (in case migration partially ran)
    unless column_exists?(:tool_clause_subcheckpoint_assignments, :assigner_user_id)
      add_reference :tool_clause_subcheckpoint_assignments, :assigner_user,
                    null: true,
                    foreign_key: { to_table: :users },
                    type: :uuid,
                    index: true
    else
      # Column exists but index might be missing
      unless index_exists?(:tool_clause_subcheckpoint_assignments, :assigner_user_id)
        add_index :tool_clause_subcheckpoint_assignments, :assigner_user_id
      end
    end
  end

  def down
    remove_reference :tool_clause_subcheckpoint_assignments, :assigner_user,
                     foreign_key: { to_table: :users }
  end
end
