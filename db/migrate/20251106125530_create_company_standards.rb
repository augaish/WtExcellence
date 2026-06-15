class CreateCompanyStandards < ActiveRecord::Migration[8.0]
  def change
    create_table :company_standards, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :company_id, null: false
      t.uuid :standard_id, null: false
      t.string :status, null: false, default: 'active' # active, inactive, archived
      t.uuid :active_version_id, null: false
      t.uuid :assigned_by
      t.datetime :assigned_at, default: -> { "now()" }
      t.text :notes

      t.timestamps
    end

    add_index :company_standards, [ :company_id, :standard_id ], unique: true
    add_index :company_standards, :company_id
    add_index :company_standards, :standard_id
    add_index :company_standards, :active_version_id
    add_index :company_standards, :assigned_by

    add_foreign_key :company_standards, :companies, column: :company_id
    add_foreign_key :company_standards, :standards, column: :standard_id
    add_foreign_key :company_standards, :standard_versions, column: :active_version_id
    add_foreign_key :company_standards, :users, column: :assigned_by
  end
end
