class CreateExecutiveAuthorities < ActiveRecord::Migration[8.0]
  def change
    # The categories the matrix is divided into (فئات الصلاحيات) — seventeen in
    # the source document, but every company defines its own.
    create_table :authority_categories, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :company, type: :uuid, null: false, foreign_key: true
      t.string :code, limit: 50
      t.string :name_en, limit: 250
      t.string :name_ar, limit: 250
      t.integer :sort_order, null: false, default: 0
      t.timestamps
    end

    # One authority: a power to decide something. It belongs to a matrix
    # version — the executive_doa record that governs it — so two versions can
    # coexist and be compared, which is what replaces the manual
    # "الاضافات والتعديلات" sheet.
    create_table :authorities, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :company, type: :uuid, null: false, foreign_key: true
      t.references :matrix, type: :uuid, null: false, foreign_key: { to_table: :pp_records }
      t.references :authority_category, type: :uuid, null: true, foreign_key: true
      t.integer :number
      t.string :name_en, limit: 500
      t.string :name_ar, limit: 500
      t.text :notes

      # The regulation or policy the authority derives from. The source matrix
      # states that all authority flows from the Minister but records no basis
      # per row, which is the first thing an auditor asks for.
      t.references :basis_record, type: :uuid, null: true, foreign_key: { to_table: :pp_records }
      t.references :basis_clause, type: :uuid, null: true, foreign_key: { to_table: :clauses }

      t.boolean :conflict_sensitive, null: false, default: false
      t.integer :sort_order, null: false, default: 0
      t.timestamps
    end
    add_index :authorities, [ :matrix_id, :number ]

    # A threshold band. The source matrix repeats a whole row — and its twenty
    # role cells — once per money bracket, so one edit has to be made four times
    # consistently. One authority with N bands removes that entire class of
    # drift. An authority with no thresholds has exactly one unbounded band.
    create_table :authority_bands, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :authority, type: :uuid, null: false, foreign_key: true
      t.string :label_en, limit: 250
      t.string :label_ar, limit: 250
      t.decimal :min_amount, precision: 15, scale: 2
      t.decimal :max_amount, precision: 15, scale: 2
      t.integer :sort_order, null: false, default: 0
      t.timestamps
    end

    # Who holds which level for that band. A holder is an org unit where one can
    # be named, or a dynamic role where the source says "الوكيل المعني" — the
    # concerned deputy — which no reader can resolve at audit time.
    create_table :authority_assignments, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :authority_band, type: :uuid, null: false, foreign_key: true
      t.string :level, limit: 20, null: false
      t.references :org_unit, type: :uuid, null: true, foreign_key: true
      t.string :dynamic_role, limit: 40
      t.string :holder_title, limit: 250
      t.string :condition, limit: 300
      t.integer :sort_order, null: false, default: 0
      t.timestamps
    end
    add_index :authority_assignments, [ :authority_band_id, :level ]
  end
end
