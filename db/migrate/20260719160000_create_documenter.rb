class CreateDocumenter < ActiveRecord::Migration[8.0]
  # Phase 3: the Documenter (الموثِّق) — the lifecycle tracker.
  #
  # Durations are measured from SYSTEM timestamps only: a stage's clock starts
  # when the record enters it (a transition row) and stops when it leaves, or —
  # for approval chains — when the last approval is marked received. No date is
  # ever typed, so the numbers cannot drift from what actually happened.
  def change
    # Every move, forward or back, with who and (for returns) why.
    create_table :pp_stage_transitions, id: :uuid do |t|
      t.references :pp_record, null: false, foreign_key: true, type: :uuid
      t.string :from_stage, limit: 50
      t.string :to_stage, limit: 50, null: false
      t.string :direction, limit: 10, null: false, default: "forward"
      t.references :actor_user, foreign_key: { to_table: :users }, type: :uuid
      t.text :reason

      t.timestamps
    end
    add_index :pp_stage_transitions, [ :pp_record_id, :created_at ]

    # An approval chain: one row per org unit asked to approve at that stage.
    create_table :pp_stage_approvals, id: :uuid do |t|
      t.references :pp_record, null: false, foreign_key: true, type: :uuid
      t.string :stage_key, limit: 50, null: false
      t.references :org_unit, null: false, foreign_key: true, type: :uuid
      t.datetime :requested_at, null: false
      t.datetime :received_at
      t.references :requested_by, foreign_key: { to_table: :users }, type: :uuid
      t.references :received_by, foreign_key: { to_table: :users }, type: :uuid
      t.text :notes

      t.timestamps
    end
    add_index :pp_stage_approvals, [ :pp_record_id, :stage_key, :org_unit_id ],
      unique: true, name: "idx_pp_stage_approvals_unique"

    # Who may act on a record at a given stage (in addition to admin/QM/owner).
    create_table :pp_stage_assignees, id: :uuid do |t|
      t.references :pp_record, null: false, foreign_key: true, type: :uuid
      t.string :stage_key, limit: 50, null: false
      t.references :user, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end
    add_index :pp_stage_assignees, [ :pp_record_id, :stage_key, :user_id ],
      unique: true, name: "idx_pp_stage_assignees_unique"

    # Per-company target duration for each stage, in working days.
    create_table :pp_stage_targets, id: :uuid do |t|
      t.references :company, null: false, foreign_key: true, type: :uuid
      t.string :stage_key, limit: 50, null: false
      t.integer :target_days, null: false, default: 0

      t.timestamps
    end
    add_index :pp_stage_targets, [ :company_id, :stage_key ], unique: true

    # Named non-working ranges excluded from working-day counts.
    create_table :company_holidays, id: :uuid do |t|
      t.references :company, null: false, foreign_key: true, type: :uuid
      t.string :name, limit: 200
      t.date :start_date, null: false
      t.date :end_date, null: false

      t.timestamps
    end
    add_index :company_holidays, [ :company_id, :start_date ]

    # Weekend is configurable; Ruby wday numbers, default Friday + Saturday.
    add_column :companies, :weekend_days, :jsonb, null: false, default: [ 5, 6 ]

    change_table :pp_records, bulk: true do |t|
      # The intersections answer captured at s2_confirmation; it routes the record.
      t.boolean :has_intersections, null: false, default: false
      # When the record entered its current stage (system-stamped).
      t.datetime :stage_entered_at
      # Reopen-as-new-version chain.
      t.integer :version_number, null: false, default: 1
      t.references :previous_version, foreign_key: { to_table: :pp_records }, type: :uuid
    end
  end
end
