# frozen_string_literal: true

class MoveStatusScoreDueDateToAssignmentContainer < ActiveRecord::Migration[7.2]
  def up
    # Add status, score, percentage_score, due_date to the container
    add_column :tool_clause_subcheckpoint_assignments, :status, :string, default: "not_started", null: false
    add_column :tool_clause_subcheckpoint_assignments, :score, :decimal, precision: 10, scale: 2
    add_column :tool_clause_subcheckpoint_assignments, :percentage_score, :decimal, precision: 5, scale: 2
    add_column :tool_clause_subcheckpoint_assignments, :due_date, :date
    add_index :tool_clause_subcheckpoint_assignments, :percentage_score, name: "idx_tcsa_on_percentage_score"

    # Migrate: for each container, take from the most recently updated user link
    execute <<-SQL.squish
      UPDATE tool_clause_subcheckpoint_assignments tcsa
      SET
        status = sub.status,
        score = sub.score,
        percentage_score = sub.percentage_score,
        due_date = sub.due_date
      FROM (
        SELECT DISTINCT ON (tool_clause_subcheckpoint_assignment_id)
          tool_clause_subcheckpoint_assignment_id,
          status,
          score,
          percentage_score,
          due_date
        FROM tool_clause_subcheckpoint_assignments_users
        ORDER BY tool_clause_subcheckpoint_assignment_id, updated_at DESC
      ) sub
      WHERE tcsa.id = sub.tool_clause_subcheckpoint_assignment_id
    SQL

    # Remove from join table
    remove_column :tool_clause_subcheckpoint_assignments_users, :status
    remove_column :tool_clause_subcheckpoint_assignments_users, :score
    remove_column :tool_clause_subcheckpoint_assignments_users, :percentage_score
    remove_column :tool_clause_subcheckpoint_assignments_users, :due_date
  end

  def down
    add_column :tool_clause_subcheckpoint_assignments_users, :status, :string, default: "not_started", null: false
    add_column :tool_clause_subcheckpoint_assignments_users, :score, :decimal, precision: 10, scale: 2
    add_column :tool_clause_subcheckpoint_assignments_users, :percentage_score, :decimal, precision: 5, scale: 2
    add_column :tool_clause_subcheckpoint_assignments_users, :due_date, :date

    execute <<-SQL.squish
      UPDATE tool_clause_subcheckpoint_assignments_users u
      SET status = tcsa.status, score = tcsa.score, percentage_score = tcsa.percentage_score, due_date = tcsa.due_date
      FROM tool_clause_subcheckpoint_assignments tcsa
      WHERE u.tool_clause_subcheckpoint_assignment_id = tcsa.id
    SQL

    remove_index :tool_clause_subcheckpoint_assignments, name: "idx_tcsa_on_percentage_score" if index_exists?(:tool_clause_subcheckpoint_assignments, :percentage_score, name: "idx_tcsa_on_percentage_score")
    remove_column :tool_clause_subcheckpoint_assignments, :status
    remove_column :tool_clause_subcheckpoint_assignments, :score
    remove_column :tool_clause_subcheckpoint_assignments, :percentage_score
    remove_column :tool_clause_subcheckpoint_assignments, :due_date
  end
end
