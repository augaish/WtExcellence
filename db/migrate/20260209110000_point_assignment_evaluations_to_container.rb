# frozen_string_literal: true

class PointAssignmentEvaluationsToContainer < ActiveRecord::Migration[8.0]
  def up
    remove_foreign_key :assignment_evaluations, column: :assignment_id
    execute "DELETE FROM assignment_evaluations"
    add_foreign_key :assignment_evaluations, :tool_clause_subcheckpoint_assignments, column: :assignment_id
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
