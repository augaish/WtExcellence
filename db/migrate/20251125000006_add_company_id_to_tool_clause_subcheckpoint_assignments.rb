class AddCompanyIdToToolClauseSubcheckpointAssignments < ActiveRecord::Migration[8.0]
  def up
    # Add company_id column if it doesn't exist
    unless column_exists?(:tool_clause_subcheckpoint_assignments, :company_id)
      add_reference :tool_clause_subcheckpoint_assignments,
                    :company,
                    type: :uuid,
                    null: true,
                    foreign_key: true
    end

    # Backfill existing rows from the user's company (via company_users)
    execute <<-SQL.squish
      UPDATE tool_clause_subcheckpoint_assignments AS a
      SET company_id = cu.company_id
      FROM company_users AS cu
      WHERE cu.user_id = a.user_id
        AND a.company_id IS NULL
    SQL

    # Add an index explicitly (add_reference may already add one, but this is idempotent)
    unless index_exists?(:tool_clause_subcheckpoint_assignments, :company_id)
      add_index :tool_clause_subcheckpoint_assignments, :company_id
    end
  end

  def down
    if column_exists?(:tool_clause_subcheckpoint_assignments, :company_id)
      remove_reference :tool_clause_subcheckpoint_assignments,
                       :company,
                       type: :uuid,
                       foreign_key: true
    end
  end
end
