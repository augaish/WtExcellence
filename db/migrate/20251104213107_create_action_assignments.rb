class CreateActionAssignments < ActiveRecord::Migration[8.0]
  def change
    create_table :capa_action_assignments, id: :uuid do |t|
      t.references :capa_action, null: false, foreign_key: true, type: :uuid
      t.references :company_user, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end

    add_index :capa_action_assignments, [ :capa_action_id, :company_user_id ], unique: true
  end
end
