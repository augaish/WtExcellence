class CreateAssignmentEvaluations < ActiveRecord::Migration[8.0]
  def up
    unless table_exists?(:assignment_evaluations)
      create_table :assignment_evaluations, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
        t.references :assignment, null: false, foreign_key: { to_table: :tool_clause_subcheckpoint_assignments }, type: :uuid, index: true
        t.references :evaluator, null: false, foreign_key: { to_table: :users }, type: :uuid, index: true
        t.decimal :score
        t.string :evaluation_status, null: false # 'approved' or 'rejected'
        t.text :feedback
        t.text :comments

        t.timestamps
      end

      # Add unique index for assignment_id and evaluator_id combination
      add_index :assignment_evaluations, [ :assignment_id, :evaluator_id ], unique: true unless index_exists?(:assignment_evaluations, [ :assignment_id, :evaluator_id ])
    else
      # Table exists, just add missing indexes if needed
      unless index_exists?(:assignment_evaluations, :assignment_id)
        add_index :assignment_evaluations, :assignment_id
      end
      unless index_exists?(:assignment_evaluations, :evaluator_id)
        add_index :assignment_evaluations, :evaluator_id
      end
      unless index_exists?(:assignment_evaluations, [ :assignment_id, :evaluator_id ])
        add_index :assignment_evaluations, [ :assignment_id, :evaluator_id ], unique: true
      end
    end
  end

  def down
    drop_table :assignment_evaluations if table_exists?(:assignment_evaluations)
  end
end
