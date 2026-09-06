class CreateOrgStructure < ActiveRecord::Migration[8.0]
  # Org Structure foundation for the P&P module.
  #
  # Two independent concepts, per the product spec:
  #   * LEVEL  = rank (1..6). Drives the reporting line: a unit's parent must
  #              hold a higher rank (a smaller level number). Level NAMES are
  #              per-company (Minister/VM/Deputy/... vs CEO/VP/ED/...).
  #   * GROUP  = a per-company classification used for colour coding only.
  def change
    # Per-company names for each rank, e.g. 1 => "CEO", 2 => "VP".
    create_table :org_level_definitions, id: :uuid do |t|
      t.references :company, null: false, foreign_key: true, type: :uuid
      t.integer :level, null: false
      t.string :name_en, limit: 100
      t.string :name_ar, limit: 100

      t.timestamps
    end
    add_index :org_level_definitions, [ :company_id, :level ], unique: true

    # Colour-coded classification (e.g. "Business", "Support").
    create_table :org_groups, id: :uuid do |t|
      t.references :company, null: false, foreign_key: true, type: :uuid
      t.string :name_en, limit: 150
      t.string :name_ar, limit: 150
      t.string :color, limit: 7, null: false, default: "#5C3984"
      t.integer :sort_order, null: false, default: 0

      t.timestamps
    end
    add_index :org_groups, :company_id, name: "index_org_groups_on_company"

    create_table :org_units, id: :uuid do |t|
      t.references :company, null: false, foreign_key: true, type: :uuid
      t.references :parent, foreign_key: { to_table: :org_units }, type: :uuid
      t.references :org_group, foreign_key: true, type: :uuid
      t.integer :level, null: false, default: 1
      t.string :code, limit: 50
      t.string :name_en, limit: 250
      t.string :name_ar, limit: 250
      t.references :head_user, foreign_key: { to_table: :users }, type: :uuid
      t.string :cost_center, limit: 100
      t.string :email, limit: 255
      t.jsonb :mandates, null: false, default: []
      t.integer :sort_order, null: false, default: 0
      t.boolean :active, null: false, default: true

      t.timestamps
    end
    add_index :org_units, [ :company_id, :code ], unique: true, where: "code IS NOT NULL"
    add_index :org_units, [ :company_id, :level ]

    # Optional: which unit a user belongs to (drives defaults and assignees).
    add_reference :users, :org_unit, foreign_key: { to_table: :org_units }, type: :uuid, null: true
  end
end
