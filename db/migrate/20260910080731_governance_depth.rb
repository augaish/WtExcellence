# Section 8 of Review 03: what a risk register and a commitments register
# need before a leader can act on them - the statement behind a risk, its
# treatment and controls, when it is next reviewed, who accepted it and until
# when; and for a commitment, the agreement it comes from, what "done" means,
# when it was delivered and whether the customer accepted it.
class GovernanceDepth < ActiveRecord::Migration[8.0]
  def change
    change_table :risks do |t|
      t.text :cause
      t.text :event
      t.text :impact_statement
      t.string :treatment_strategy, limit: 20          # avoid | reduce | transfer | accept
      t.text :treatment_plan
      t.uuid :control_owner_id                          # CompanyUser
      t.text :control_rationale                         # why the residual score is what it is
      t.date :next_review_on
      # Acceptance of exposure above appetite: who, why, until when.
      t.uuid :accepted_by_id
      t.datetime :accepted_at
      t.text :acceptance_rationale
      t.date :acceptance_expires_on
    end
    add_foreign_key :risks, :company_users, column: :control_owner_id, on_delete: :nullify
    add_foreign_key :risks, :users, column: :accepted_by_id, on_delete: :nullify
    add_index :risks, :next_review_on

    change_table :customer_commitments do |t|
      t.string :agreement_reference, limit: 250
      t.text :acceptance_criteria
      t.date :delivered_on
      t.uuid :verified_by_id
      t.string :acceptance_status, limit: 20, null: false, default: "pending"   # pending | accepted | rejected
      t.text :acceptance_note
      t.string :recurrence, limit: 20, null: false, default: "none"           # none | monthly | quarterly | annual
      t.uuid :vendor_id
      t.uuid :recurred_from_id
    end
    add_foreign_key :customer_commitments, :users, column: :verified_by_id, on_delete: :nullify
    add_foreign_key :customer_commitments, :vendors, on_delete: :nullify
    add_foreign_key :customer_commitments, :customer_commitments, column: :recurred_from_id, on_delete: :nullify
  end
end
