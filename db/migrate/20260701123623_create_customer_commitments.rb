class CreateCustomerCommitments < ActiveRecord::Migration[8.0]
  def change
    create_table :customer_commitments, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :company, null: false, foreign_key: true, type: :uuid
      t.string :title, null: false
      t.text :description
      t.string :customer_name
      t.date :due_date
      t.string :status, null: false, default: "open"
      t.references :owner, foreign_key: { to_table: :company_users }, type: :uuid
      t.references :created_by, foreign_key: { to_table: :users }, type: :uuid
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :customer_commitments, :status
    add_index :customer_commitments, :deleted_at
  end
end
