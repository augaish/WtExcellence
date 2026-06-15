class CreateClauseScoreCaches < ActiveRecord::Migration[8.0]
  def change
    create_table :clause_score_caches, id: :uuid do |t|
      t.uuid :clause_id, null: false
      t.uuid :company_id, null: false
      t.decimal :cached_score, precision: 10, scale: 2
      t.decimal :cached_percentage, precision: 5, scale: 2
      t.integer :cached_evaluated_count
      t.datetime :cached_at

      t.timestamps
    end

    add_index :clause_score_caches, [:clause_id, :company_id], unique: true, name: "index_clause_score_caches_on_clause_and_company"
    add_index :clause_score_caches, :company_id
    add_index :clause_score_caches, :cached_at
    add_foreign_key :clause_score_caches, :clauses, column: :clause_id
    add_foreign_key :clause_score_caches, :companies, column: :company_id
  end
end

