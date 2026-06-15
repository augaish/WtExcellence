class RemoveCalculatedPointsFromToolClauseSubcheckpointAssignments < ActiveRecord::Migration[8.0]
  def change
    remove_column :tool_clause_subcheckpoint_assignments, :calculated_points, :decimal, precision: 10, scale: 2
  end
end

