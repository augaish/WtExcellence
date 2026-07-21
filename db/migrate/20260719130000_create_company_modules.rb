class CreateCompanyModules < ActiveRecord::Migration[8.0]
  # Per-company module entitlements. A row exists only when a super admin has
  # explicitly set a module for a company; absence means "use the default"
  # (enabled). This keeps existing companies working with no backfill.
  def change
    create_table :company_modules, id: :uuid do |t|
      t.references :company, null: false, foreign_key: true, type: :uuid
      t.string :module_key, null: false, limit: 50
      t.boolean :enabled, null: false, default: true

      t.timestamps
    end

    add_index :company_modules, [ :company_id, :module_key ], unique: true
  end
end
