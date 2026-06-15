class AddPercentageScoreToToolClauseSubcheckpointAssignments < ActiveRecord::Migration[8.0]
  def change
    add_column :tool_clause_subcheckpoint_assignments, :percentage_score, :decimal, precision: 5, scale: 2
    add_column :tool_clause_subcheckpoint_assignments, :calculated_points, :decimal, precision: 10, scale: 2

    add_index :tool_clause_subcheckpoint_assignments, :percentage_score
  end
end








