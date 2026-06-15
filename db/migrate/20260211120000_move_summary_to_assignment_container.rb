# frozen_string_literal: true

class MoveSummaryToAssignmentContainer < ActiveRecord::Migration[7.2]
  def up
    # Add summary and last_edited_by to the container (tool_clause_subcheckpoint_assignments)
    add_column :tool_clause_subcheckpoint_assignments, :summary, :text
    add_reference :tool_clause_subcheckpoint_assignments, :last_edited_by_user, foreign_key: { to_table: :users }, type: :uuid, index: true

    # Migrate existing summary from user links to container (take most recently updated non-blank)
    reversible do |dir|
      dir.up do
        execute <<-SQL.squish
          UPDATE tool_clause_subcheckpoint_assignments tcsa
          SET
            summary = sub.summary,
            last_edited_by_user_id = sub.user_id
          FROM (
            SELECT DISTINCT ON (tool_clause_subcheckpoint_assignment_id)
              tool_clause_subcheckpoint_assignment_id,
              summary,
              user_id,
              updated_at
            FROM tool_clause_subcheckpoint_assignments_users
            WHERE summary IS NOT NULL AND summary != ''
            ORDER BY tool_clause_subcheckpoint_assignment_id, updated_at DESC
          ) sub
          WHERE tcsa.id = sub.tool_clause_subcheckpoint_assignment_id
        SQL
      end
    end

    # Remove summary from the join table (only links users to container)
    remove_column :tool_clause_subcheckpoint_assignments_users, :summary
  end

  def down
    # Add summary back to join table
    add_column :tool_clause_subcheckpoint_assignments_users, :summary, :text

    # Copy container summary to each user link for this container (lossy: same content for all)
    execute <<-SQL.squish
      UPDATE tool_clause_subcheckpoint_assignments_users u
      SET summary = tcsa.summary
      FROM tool_clause_subcheckpoint_assignments tcsa
      WHERE u.tool_clause_subcheckpoint_assignment_id = tcsa.id
    SQL

    # Remove from container
    remove_reference :tool_clause_subcheckpoint_assignments, :last_edited_by_user, foreign_key: { to_table: :users }, type: :uuid
    remove_column :tool_clause_subcheckpoint_assignments, :summary
  end
end
