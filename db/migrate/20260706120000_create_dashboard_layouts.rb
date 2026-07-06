class CreateDashboardLayouts < ActiveRecord::Migration[8.0]
  def change
    create_table :dashboard_layouts do |t|
      t.references :company, type: :uuid, foreign_key: true, null: true
      t.string :scope, null: false, default: "company"
      t.integer :slot, null: false, default: 1
      t.string :name
      t.jsonb :config, null: false, default: {}
      t.boolean :is_active, null: false, default: false

      t.timestamps
    end

    add_index :dashboard_layouts, [ :company_id, :scope, :slot ], unique: true, name: "index_dashboard_layouts_on_company_scope_slot"
  end
end
