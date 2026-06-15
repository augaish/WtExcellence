class CreateAssessmentModelRefactor < ActiveRecord::Migration[8.0]
  def up
    # ── Step 1: Create new tables ──────────────────────────────────────

    create_table :assessments, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :tool_clause_id, null: false
      t.uuid :company_id, null: false
      t.string :status, default: "not_started", null: false
      t.date :due_date
      t.uuid :last_edited_by_user_id
      t.timestamps
    end

    add_index :assessments, [:tool_clause_id, :company_id], unique: true, name: "idx_assessments_unique_tool_clause_company"
    add_index :assessments, :tool_clause_id
    add_index :assessments, :company_id
    add_index :assessments, :status
    add_foreign_key :assessments, :tool_clauses
    add_foreign_key :assessments, :companies
    add_foreign_key :assessments, :users, column: :last_edited_by_user_id

    create_table :assessment_scores, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :assessment_id, null: false
      t.bigint :tool_subcheckpoint_id, null: false
      t.decimal :score, precision: 10, scale: 2
      t.decimal :percentage_score, precision: 5, scale: 2
      t.timestamps
    end

    add_index :assessment_scores, [:assessment_id, :tool_subcheckpoint_id], unique: true, name: "idx_assessment_scores_unique"
    add_index :assessment_scores, :assessment_id
    add_index :assessment_scores, :tool_subcheckpoint_id
    add_foreign_key :assessment_scores, :assessments
    add_foreign_key :assessment_scores, :tool_subcheckpoints

    create_table :assessment_users, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :assessment_id, null: false
      t.uuid :user_id, null: false
      t.string :role, null: false # "contributor" or "auditor"
      t.bigint :tool_subcheckpoint_id # nullable — for contributor checkpoint mapping
      t.uuid :assigner_user_id
      t.timestamps
    end

    add_index :assessment_users, [:assessment_id, :user_id, :tool_subcheckpoint_id], unique: true, name: "idx_assessment_users_unique"
    add_index :assessment_users, :assessment_id
    add_index :assessment_users, :user_id
    add_index :assessment_users, :tool_subcheckpoint_id
    add_foreign_key :assessment_users, :assessments
    add_foreign_key :assessment_users, :users
    add_foreign_key :assessment_users, :tool_subcheckpoints, column: :tool_subcheckpoint_id
    add_foreign_key :assessment_users, :users, column: :assigner_user_id

    # ── Step 2: Migrate data ──────────────────────────────────────────

    # Create one Assessment per unique (tool_clause_id, company_id)
    execute <<~SQL
      INSERT INTO assessments (id, tool_clause_id, company_id, status, due_date, created_at, updated_at)
      SELECT gen_random_uuid(), tool_clause_id, company_id, 'not_started',
             MAX(due_date), MIN(created_at), MAX(updated_at)
      FROM tool_clause_subcheckpoint_assignments
      WHERE company_id IS NOT NULL
      GROUP BY tool_clause_id, company_id
    SQL

    # Copy scores to assessment_scores
    execute <<~SQL
      INSERT INTO assessment_scores (id, assessment_id, tool_subcheckpoint_id, score, percentage_score, created_at, updated_at)
      SELECT gen_random_uuid(), a.id, tcsa.tool_subcheckpoint_id, tcsa.score, tcsa.percentage_score, tcsa.created_at, tcsa.updated_at
      FROM tool_clause_subcheckpoint_assignments tcsa
      JOIN assessments a ON a.tool_clause_id = tcsa.tool_clause_id AND a.company_id = tcsa.company_id
      WHERE tcsa.company_id IS NOT NULL
    SQL

    # Copy user assignments to assessment_users
    execute <<~SQL
      INSERT INTO assessment_users (id, assessment_id, user_id, role, tool_subcheckpoint_id, assigner_user_id, created_at, updated_at)
      SELECT gen_random_uuid(), a.id, tau.user_id,
             CASE WHEN cu.role = 'company_auditor' THEN 'auditor' ELSE 'contributor' END,
             tcsa.tool_subcheckpoint_id, tau.assigner_user_id, tau.created_at, tau.updated_at
      FROM tool_clause_subcheckpoint_assignments_users tau
      JOIN tool_clause_subcheckpoint_assignments tcsa ON tcsa.id = tau.tool_clause_subcheckpoint_assignment_id
      JOIN assessments a ON a.tool_clause_id = tcsa.tool_clause_id AND a.company_id = tcsa.company_id
      LEFT JOIN company_users cu ON cu.user_id = tau.user_id AND cu.company_id = tcsa.company_id
      WHERE tcsa.company_id IS NOT NULL
    SQL

    # Re-point evidence_attachments from old containers to assessments
    execute <<~SQL
      UPDATE evidence_attachments
      SET attachable_type = 'Assessment',
          attachable_id = a.id
      FROM tool_clause_subcheckpoint_assignments tcsa
      JOIN assessments a ON a.tool_clause_id = tcsa.tool_clause_id AND a.company_id = tcsa.company_id
      WHERE evidence_attachments.attachable_type = 'ToolClauseSubcheckpointAssignment'
        AND evidence_attachments.attachable_id = tcsa.id
    SQL

    # Re-point assignment_evaluations to assessments
    # First add the new FK column
    add_column :assignment_evaluations, :assessment_id_new, :uuid

    execute <<~SQL
      UPDATE assignment_evaluations
      SET assessment_id_new = a.id
      FROM tool_clause_subcheckpoint_assignments tcsa
      JOIN assessments a ON a.tool_clause_id = tcsa.tool_clause_id AND a.company_id = tcsa.company_id
      WHERE assignment_evaluations.assignment_id = tcsa.id
    SQL

    # Remove old FK, rename new one
    remove_foreign_key :assignment_evaluations, column: :assignment_id if foreign_key_exists?(:assignment_evaluations, column: :assignment_id)
    remove_column :assignment_evaluations, :assignment_id
    rename_column :assignment_evaluations, :assessment_id_new, :assessment_id
    add_index :assignment_evaluations, :assessment_id
    add_foreign_key :assignment_evaluations, :assessments, column: :assessment_id

    # ── Step 3: Drop old tables ───────────────────────────────────────

    drop_table :tool_clause_subcheckpoint_assignments_users
    drop_table :tool_clause_subcheckpoint_assignments
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "This migration drops tables and migrates data. Use a backup to restore."
  end
end
