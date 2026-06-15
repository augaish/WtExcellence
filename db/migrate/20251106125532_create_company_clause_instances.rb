class CreateCompanyClauseInstances < ActiveRecord::Migration[8.0]
  def change
    create_table :company_clause_instances, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :company_standard_id, null: false
      t.uuid :clause_id, null: false
      t.string :clause_code, limit: 100
      t.uuid :version_id, null: false

      t.timestamps
    end

    add_index :company_clause_instances, [ :company_standard_id, :clause_id ], unique: true
    add_index :company_clause_instances, :company_standard_id
    add_index :company_clause_instances, :clause_id
    add_index :company_clause_instances, :version_id
    add_index :company_clause_instances, :clause_code

    add_foreign_key :company_clause_instances, :company_standards, column: :company_standard_id
    add_foreign_key :company_clause_instances, :clauses, column: :clause_id
    add_foreign_key :company_clause_instances, :standard_versions, column: :version_id
  end
end
