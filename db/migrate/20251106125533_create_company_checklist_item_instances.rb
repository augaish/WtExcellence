class CreateCompanyChecklistItemInstances < ActiveRecord::Migration[8.0]
  def change
    create_table :company_checklist_item_instances, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :company_clause_instance_id, null: false
      t.uuid :checklist_item_id, null: false
      t.string :status, null: false, default: 'not_started' # not_started, in_progress, compliant, partially_compliant, not_compliant, not_applicable
      t.uuid :assigned_to
      t.date :due_date
      t.uuid :last_updated_by
      t.datetime :last_updated_at, default: -> { "now()" }

      t.timestamps
    end

    add_index :company_checklist_item_instances, [ :company_clause_instance_id, :checklist_item_id ], unique: true
    add_index :company_checklist_item_instances, :company_clause_instance_id
    add_index :company_checklist_item_instances, :checklist_item_id
    add_index :company_checklist_item_instances, :status
    add_index :company_checklist_item_instances, :assigned_to
    add_index :company_checklist_item_instances, :last_updated_by

    add_foreign_key :company_checklist_item_instances, :company_clause_instances, column: :company_clause_instance_id
    add_foreign_key :company_checklist_item_instances, :checklist_items, column: :checklist_item_id
    add_foreign_key :company_checklist_item_instances, :users, column: :assigned_to
    add_foreign_key :company_checklist_item_instances, :users, column: :last_updated_by
  end
end
