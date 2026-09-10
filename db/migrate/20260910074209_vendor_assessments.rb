# Vendor management the right way round: a rating comes from a dated,
# reviewed assessment with its evidence, or is set by hand with a written
# reason; approval to use a supplier is a separate state from its risk.
class VendorAssessments < ActiveRecord::Migration[8.0]
  def change
    change_table :vendors do |t|
      t.string :criticality, limit: 20                   # how much the business depends on them
      t.text :service_description
      t.date :contract_end_on
      t.date :next_review_on
      t.string :rating_source, limit: 20, null: false, default: "manual"   # manual | assessed
      t.text :rating_override_reason
      t.string :approval_status, limit: 30, null: false, default: "not_approved"
      t.text :approval_note
      t.uuid :approved_by_id
      t.datetime :approved_at
    end
    add_foreign_key :vendors, :users, column: :approved_by_id, on_delete: :nullify

    create_table :vendor_assessments, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :vendor, type: :uuid, null: false, foreign_key: true
      t.references :company, type: :uuid, null: false, foreign_key: true
      t.uuid :assessed_by_id
      t.uuid :reviewed_by_id
      t.date :assessed_on, null: false
      t.jsonb :scores, null: false, default: {}
      t.string :rating, limit: 20, null: false
      t.text :rationale
      t.date :next_review_on
      t.datetime :reviewed_at
      t.text :review_note
      t.integer :version, null: false, default: 1
      t.timestamps
    end
    add_foreign_key :vendor_assessments, :users, column: :assessed_by_id, on_delete: :nullify
    add_foreign_key :vendor_assessments, :users, column: :reviewed_by_id, on_delete: :nullify
    add_index :vendor_assessments, [ :vendor_id, :version ], unique: true
  end
end
