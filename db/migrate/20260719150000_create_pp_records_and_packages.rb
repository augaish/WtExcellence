class CreatePpRecordsAndPackages < ActiveRecord::Migration[8.0]
  # Phase 2: the register of governed content ("records") and the packages that
  # group them.
  #
  # A record belongs to AT MOST ONE package. That is modelled as a single
  # nullable FK on the record, which makes "two packages at once" structurally
  # impossible; the composition UI never lets a package silently steal another
  # package's record (see PpRecord#assign_to_package!).
  def change
    create_table :pp_packages, id: :uuid do |t|
      t.references :company, null: false, foreign_key: true, type: :uuid
      t.string :name, limit: 250, null: false
      t.date :start_date
      t.date :end_date
      t.text :notes

      t.timestamps
    end
    add_index :pp_packages, [ :company_id, :name ]

    create_table :pp_records, id: :uuid do |t|
      t.references :company, null: false, foreign_key: true, type: :uuid
      t.references :package, foreign_key: { to_table: :pp_packages }, type: :uuid

      t.string :record_type, limit: 40, null: false
      t.string :code, limit: 50
      t.string :title_en, limit: 300
      t.string :title_ar, limit: 300
      t.text :description
      t.string :version_label, limit: 50

      t.date :effective_date
      t.date :review_date

      t.references :owner_user, foreign_key: { to_table: :users }, type: :uuid
      t.references :owner_org_unit, foreign_key: { to_table: :org_units }, type: :uuid
      t.references :pp_process, foreign_key: { to_table: :pp_processes }, type: :uuid

      # Populated by the Documenter in Phase 3; unused (and unvalidated) here.
      t.string :current_stage, limit: 50

      t.boolean :active, null: false, default: true

      t.timestamps
    end
    add_index :pp_records, [ :company_id, :code ], unique: true, where: "code IS NOT NULL"
    add_index :pp_records, [ :company_id, :record_type ]
    add_index :pp_records, :review_date
  end
end
