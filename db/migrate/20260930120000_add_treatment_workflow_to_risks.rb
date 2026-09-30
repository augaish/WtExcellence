# The risk owner fills in the treatment and a risk manager accepts it or
# returns it with a reason. Risks that already carry a treatment plan were
# written by a manager, so they start accepted; the rest await their owner.
class AddTreatmentWorkflowToRisks < ActiveRecord::Migration[8.0]
  def up
    add_column :risks, :treatment_state, :string, null: false, default: "awaiting_treatment"
    add_column :risks, :treatment_submitted_at, :datetime
    add_column :risks, :treatment_reviewed_at, :datetime
    add_column :risks, :treatment_return_reason, :text
    add_reference :risks, :treatment_reviewed_by, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }, null: true
    add_index :risks, :treatment_state

    execute <<~SQL
      UPDATE risks SET treatment_state = 'treatment_accepted', treatment_reviewed_at = updated_at
      WHERE treatment_plan IS NOT NULL AND btrim(treatment_plan) <> ''
    SQL
  end

  def down
    remove_reference :risks, :treatment_reviewed_by, foreign_key: { to_table: :users }
    remove_column :risks, :treatment_return_reason
    remove_column :risks, :treatment_reviewed_at
    remove_column :risks, :treatment_submitted_at
    remove_column :risks, :treatment_state
  end
end
