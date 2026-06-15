class RemoveUniqueIndexFromAssignmentEvaluations < ActiveRecord::Migration[8.0]
  def up
    # Remove the unique index to allow multiple evaluations per assignment-evaluator pair
    if index_exists?(:assignment_evaluations, [:assignment_id, :evaluator_id], unique: true)
      remove_index :assignment_evaluations, [:assignment_id, :evaluator_id]
    end
    
    # Add a non-unique index for performance (still need to query by assignment and evaluator)
    unless index_exists?(:assignment_evaluations, [:assignment_id, :evaluator_id])
      add_index :assignment_evaluations, [:assignment_id, :evaluator_id]
    end
  end

  def down
    # Remove the non-unique index
    if index_exists?(:assignment_evaluations, [:assignment_id, :evaluator_id])
      remove_index :assignment_evaluations, [:assignment_id, :evaluator_id]
    end
    
    # Re-add the unique index
    unless index_exists?(:assignment_evaluations, [:assignment_id, :evaluator_id], unique: true)
      add_index :assignment_evaluations, [:assignment_id, :evaluator_id], unique: true
    end
  end
end

