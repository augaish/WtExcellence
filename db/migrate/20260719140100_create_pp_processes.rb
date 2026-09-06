class CreatePpProcesses < ActiveRecord::Migration[8.0]
  # Process Architecture: a 3-level tree (level 1 -> 2 -> 3) with a category on
  # the top level. Phase 1 populates category + levels 1 and 2; level 3 is where
  # individual procedures are documented later.
  #
  # The card fields mirror the ministry's process form 1:1. trigger_text /
  # inputs / outputs double as the process-level summary the efficiency
  # evaluator reads, so they are captured once here and never re-entered.
  def change
    create_table :pp_processes, id: :uuid do |t|
      t.references :company, null: false, foreign_key: true, type: :uuid
      t.references :parent, foreign_key: { to_table: :pp_processes }, type: :uuid
      t.integer :level, null: false, default: 1
      t.string :category, limit: 30
      t.string :code, limit: 50
      t.string :name_en, limit: 250
      t.string :name_ar, limit: 250

      t.text :objective
      t.references :owner_org_unit, foreign_key: { to_table: :org_units }, type: :uuid
      t.references :owner_user, foreign_key: { to_table: :users }, type: :uuid
      t.text :trigger_text
      t.text :inputs
      t.text :outputs

      t.references :predecessor_process, foreign_key: { to_table: :pp_processes }, type: :uuid
      t.references :successor_process, foreign_key: { to_table: :pp_processes }, type: :uuid

      t.string :frequency, limit: 50
      t.decimal :total_time_value, precision: 10, scale: 2
      t.string :total_time_unit, limit: 20
      t.string :automation_status, limit: 50

      # Free text in Phase 1; becomes links to Policy/Form records in Phase 2.
      t.text :related_policies
      t.text :technical_systems
      t.text :forms_used
      t.text :kpis

      t.integer :sort_order, null: false, default: 0
      t.boolean :active, null: false, default: true

      t.timestamps
    end
    add_index :pp_processes, [ :company_id, :code ], unique: true, where: "code IS NOT NULL"
    add_index :pp_processes, [ :company_id, :level ]
  end
end
