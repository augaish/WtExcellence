# frozen_string_literal: true

class RefactorAssignmentsOnePerSubcheckpointUsersJoin < ActiveRecord::Migration[8.0]
  def up
    # 1. Clear all dependent data and then assignment/user tables (no data migration)
    execute "DELETE FROM evidence_attachments WHERE attachable_type = 'ToolClauseSubcheckpointAssignment'"
    execute "DELETE FROM assignment_evaluations"
    execute "DELETE FROM tool_clause_subcheckpoint_assignments"
    execute "DELETE FROM tool_users"

    # 2. Rename current table so we can create the new "one assignment" table
    rename_table :tool_clause_subcheckpoint_assignments, :tool_clause_subcheckpoint_assignments_old

    # Use the same type as tool_subcheckpoints.id so FK works (production may have bigint, local may have uuid)
    tool_subcheckpoint_id_type = column_type_for(:tool_subcheckpoints, :id)

    # 3. Create new tool_clause_subcheckpoint_assignments: one row per (tool_clause, subcheckpoint, company)
    create_table :tool_clause_subcheckpoint_assignments, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :tool_clause, null: false, type: :uuid, foreign_key: true, index: true
      t.references :tool_subcheckpoint, null: false, type: tool_subcheckpoint_id_type, foreign_key: { to_table: :tool_subcheckpoints, column: :id }, index: true
      t.references :company, null: true, type: :uuid, foreign_key: true, index: true
      t.timestamps
    end
    add_index :tool_clause_subcheckpoint_assignments,
              %i[tool_clause_id tool_subcheckpoint_id company_id],
              unique: true,
              name: "index_tcsa_on_tool_clause_subcheckpoint_company"

    # 4. Create join table: which users are on each assignment (per-user state lives here)
    create_table :tool_clause_subcheckpoint_assignments_users, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :tool_clause_subcheckpoint_assignment, null: false, type: :uuid, foreign_key: true, index: true
      t.references :user, null: false, type: :uuid, foreign_key: true, index: true
      t.string :status, comment: "Status values: not_started, in_drafts, under_review, auditor_approved, approved, needs_changes"
      t.decimal :score
      t.text :summary
      t.decimal :percentage_score, precision: 5, scale: 2
      t.date :due_date
      t.references :assigner_user, type: :uuid, foreign_key: { to_table: :users, column: :id }, index: true
      t.timestamps
    end
    add_index :tool_clause_subcheckpoint_assignments_users,
              %i[tool_clause_subcheckpoint_assignment_id user_id],
              unique: true,
              name: "index_tcsa_users_on_assignment_id_and_user_id"
    add_index :tool_clause_subcheckpoint_assignments_users, :percentage_score, name: "idx_tcsa_users_on_percentage_score"

    # 5. Point assignment_evaluations to the new join table
    remove_foreign_key :assignment_evaluations, column: :assignment_id
    add_foreign_key :assignment_evaluations, :tool_clause_subcheckpoint_assignments_users, column: :assignment_id

    # 6. Drop old table and tool_users
    drop_table :tool_clause_subcheckpoint_assignments_old
    drop_table :tool_users
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Cannot reverse refactor: old table had different structure"
  end

  private

  def column_type_for(table_name, column_name)
    col = connection.columns(table_name).find { |c| c.name == column_name.to_s }
    raise "Column #{table_name}.#{column_name} not found" unless col
    # Map PostgreSQL type to Rails reference type (must match exactly for FK)
    case col.sql_type
    when "uuid" then :uuid
    when "bigint" then :bigint
    when "integer" then :integer
    else
      raise "Unsupported type for FK: #{col.sql_type} (table=#{table_name}, column=#{column_name})"
    end
  end
end
