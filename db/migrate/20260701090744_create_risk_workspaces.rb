class CreateRiskWorkspaces < ActiveRecord::Migration[8.0]
  def change
    create_table :risk_workspaces, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :company, null: false, foreign_key: true, type: :uuid
      t.string :name, null: false
      t.string :framework
      t.text :description
      t.string :department_scope
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :risk_workspaces, :deleted_at

    add_reference :risks, :risk_workspace, foreign_key: true, type: :uuid, null: true
  end
end
