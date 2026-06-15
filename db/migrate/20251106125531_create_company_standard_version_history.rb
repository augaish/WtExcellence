class CreateCompanyStandardVersionHistory < ActiveRecord::Migration[8.0]
  def change
    create_table :company_standard_version_history, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :company_standard_id, null: false
      t.uuid :from_version_id
      t.uuid :to_version_id, null: false
      t.uuid :changed_by
      t.datetime :changed_at, default: -> { "now()" }
      t.text :reason

      t.timestamps
    end

    add_index :company_standard_version_history, :company_standard_id
    add_index :company_standard_version_history, :from_version_id
    add_index :company_standard_version_history, :to_version_id
    add_index :company_standard_version_history, :changed_by
    add_index :company_standard_version_history, :changed_at

    add_foreign_key :company_standard_version_history, :company_standards, column: :company_standard_id
    add_foreign_key :company_standard_version_history, :standard_versions, column: :from_version_id
    add_foreign_key :company_standard_version_history, :standard_versions, column: :to_version_id
    add_foreign_key :company_standard_version_history, :users, column: :changed_by
  end
end
