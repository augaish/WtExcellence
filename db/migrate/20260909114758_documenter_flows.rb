# The Documenter flows as the product owner described them: one sequence for
# policies, forms and services; the same with a design pair for procedures; a
# single approval for glossary terms. Everything the old lifecycle stored was
# test data and is cleared so the new flows start clean.
class DocumenterFlows < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      DELETE FROM pp_diagram_flows WHERE pp_diagram_id IN (SELECT id FROM pp_diagrams WHERE owner_type = 'PpRecord');
      DELETE FROM pp_diagram_elements WHERE pp_diagram_id IN (SELECT id FROM pp_diagrams WHERE owner_type = 'PpRecord');
      DELETE FROM pp_diagrams WHERE owner_type = 'PpRecord';
      DELETE FROM pp_stage_transitions;
      DELETE FROM pp_stage_approvals;
      DELETE FROM pp_stage_assignees;
      DELETE FROM pp_record_links;
      DELETE FROM pp_record_participants;
      DELETE FROM pp_record_terms;
      DELETE FROM pp_record_references;
      DELETE FROM pp_service_levels;
      DELETE FROM evidence_attachments WHERE attachable_type = 'PpRecord';
      UPDATE pp_records SET previous_version_id = NULL, predecessor_record_id = NULL, successor_record_id = NULL;
      -- Anything else that points at a record being removed: an authority's
      -- basis policy, a delegation's decision record. The matrices themselves stay.
      UPDATE authorities SET basis_record_id = NULL
        WHERE basis_record_id IN (SELECT id FROM pp_records WHERE record_type NOT IN ('executive_doa', 'operational_doa'));
      UPDATE authority_delegations SET decision_record_id = NULL
        WHERE decision_record_id IN (SELECT id FROM pp_records WHERE record_type NOT IN ('executive_doa', 'operational_doa'));
      DELETE FROM pp_records WHERE record_type NOT IN ('executive_doa', 'operational_doa');
      UPDATE pp_records SET current_stage = NULL, stage_entered_at = NULL;
    SQL

    # P&P Managers: quality managers the company admin names in Account Management.
    add_column :company_users, :pp_manager, :boolean, null: false, default: false

    change_table :pp_records do |t|
      t.uuid :verifier_user_id                 # Data Verification: the contributor the logger chose
      t.integer :auto_approve_days             # Stakeholder / Final Approval: silence = approval after N working days
      t.string :publish_mode, limit: 20        # 'assign' (a publisher pastes the link) or 'system'
      t.string :published_link, limit: 1000
      t.datetime :published_at
      t.uuid :published_pdf_upload_id
    end
    add_foreign_key :pp_records, :users, column: :verifier_user_id, on_delete: :nullify
    add_foreign_key :pp_records, :uploads, column: :published_pdf_upload_id, on_delete: :nullify

    # Steps belong to the procedure record; they are filled in the Documenter.
    add_reference :pp_process_steps, :pp_record, type: :uuid, foreign_key: true
    change_column_null :pp_process_steps, :pp_process_id, true
    add_index :pp_process_steps, [ :pp_record_id, :position ]

    # Clauses of a policy (main clause, sub-clauses beneath), and the comments
    # reviewers leave on each one.
    create_table :pp_record_clauses, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :pp_record, type: :uuid, null: false, foreign_key: true
      t.uuid :parent_id
      t.integer :position, null: false, default: 1
      t.string :title, limit: 300
      t.text :body
      t.timestamps
    end
    add_foreign_key :pp_record_clauses, :pp_record_clauses, column: :parent_id, on_delete: :cascade
    add_index :pp_record_clauses, [ :pp_record_id, :parent_id, :position ]

    create_table :pp_clause_comments, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :pp_record_clause, type: :uuid, null: false, foreign_key: true
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.string :stage_key, limit: 50
      t.text :body, null: false
      t.datetime :resolved_at
      t.timestamps
    end

    # A piece of work handed to one person inside a stage: the reviewer who
    # fills the clauses, the designer who draws, the publisher who posts.
    create_table :pp_stage_tasks, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :pp_record, type: :uuid, null: false, foreign_key: true
      t.string :stage_key, limit: 50, null: false
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.uuid :assigned_by_id
      t.datetime :assigned_at, null: false
      t.datetime :submitted_at
      t.text :note
      t.timestamps
    end
    add_index :pp_stage_tasks, [ :pp_record_id, :stage_key ]

    # Approvals answered by the unit head, in parallel or in sequence groups,
    # with a decision rather than a bare "received".
    change_table :pp_stage_approvals do |t|
      t.string :decision, limit: 20            # approved / rejected / auto_approved
      t.text :comment
      t.integer :sequence_group, null: false, default: 1
      t.datetime :auto_approve_at
    end
  end

  def down
    remove_column :pp_stage_approvals, :auto_approve_at
    remove_column :pp_stage_approvals, :sequence_group
    remove_column :pp_stage_approvals, :comment
    remove_column :pp_stage_approvals, :decision
    drop_table :pp_stage_tasks
    drop_table :pp_clause_comments
    drop_table :pp_record_clauses
    remove_index :pp_process_steps, [ :pp_record_id, :position ]
    remove_reference :pp_process_steps, :pp_record
    remove_foreign_key :pp_records, column: :published_pdf_upload_id
    remove_foreign_key :pp_records, column: :verifier_user_id
    remove_columns :pp_records, :verifier_user_id, :auto_approve_days, :publish_mode, :published_link, :published_at, :published_pdf_upload_id
    remove_column :company_users, :pp_manager
  end
end
