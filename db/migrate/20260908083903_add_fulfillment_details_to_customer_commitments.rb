class AddFulfillmentDetailsToCustomerCommitments < ActiveRecord::Migration[8.0]
  def up
    # Fulfilling an obligation recorded nothing about when it actually happened,
    # who confirmed it, or on what basis — so "Fulfilled" could not be told from
    # "Fulfilled three weeks late".
    add_column :customer_commitments, :fulfilled_at, :datetime
    add_column :customer_commitments, :fulfilled_by_id, :uuid
    add_column :customer_commitments, :fulfillment_note, :text
    add_index :customer_commitments, :fulfilled_by_id

    # "overdue" was a status a user could pick, which mixed timing in with the
    # workflow state: an obligation could be marked Overdue while on time, or sit
    # at Open while weeks past due. Timing is now derived from the due date, so
    # records carrying the old status move to the workflow state they were
    # actually in.
    execute <<~SQL
      UPDATE customer_commitments SET status = 'in_progress' WHERE status = 'overdue'
    SQL
  end

  def down
    remove_index :customer_commitments, :fulfilled_by_id
    remove_column :customer_commitments, :fulfilled_at
    remove_column :customer_commitments, :fulfilled_by_id
    remove_column :customer_commitments, :fulfillment_note
  end
end
