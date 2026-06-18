class CreateRisks < ActiveRecord::Migration[8.0]
  def change
    create_table :risks, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :company, null: false, foreign_key: true, type: :uuid
      t.references :owner, foreign_key: { to_table: :company_users }, type: :uuid
      t.references :created_by, foreign_key: { to_table: :users }, type: :uuid

      t.string :title, null: false
      t.text :description
      t.string :category

      t.uuid :riskable_id
      t.string :riskable_type, limit: 50

      t.integer :likelihood, null: false, default: 1
      t.integer :impact, null: false, default: 1
      t.integer :inherent_score, null: false, default: 1

      t.integer :residual_likelihood
      t.integer :residual_impact
      t.integer :residual_score

      t.string :status, null: false, default: "identified"
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :risks, [ :riskable_type, :riskable_id ], name: "index_risks_on_riskable"
    add_index :risks, :status
    add_index :risks, :deleted_at
  end
end
