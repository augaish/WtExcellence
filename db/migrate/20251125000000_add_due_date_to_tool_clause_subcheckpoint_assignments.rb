class AddDueDateToToolClauseSubcheckpointAssignments < ActiveRecord::Migration[8.0]
  def change
    add_column :tool_clause_subcheckpoint_assignments, :due_date, :date
  end
end


