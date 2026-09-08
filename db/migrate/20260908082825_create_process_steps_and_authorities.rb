class CreateProcessStepsAndAuthorities < ActiveRecord::Migration[8.0]
  def change
    # خطوات الإجراء — the numbered steps of a procedure. The responsible party is
    # a job position rather than a person, because a procedure outlives whoever
    # currently holds the post; an org unit may be named alongside it.
    create_table :pp_process_steps, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :pp_process, type: :uuid, null: false, foreign_key: true
      t.integer :position, null: false, default: 1
      t.string :activity, limit: 300
      t.text :description
      t.string :responsible_title, limit: 250
      t.references :responsible_org_unit, type: :uuid, null: true, foreign_key: { to_table: :org_units }
      t.decimal :duration_value, precision: 10, scale: 2
      t.string :duration_unit, limit: 20
      t.string :system_used, limit: 250
      t.timestamps
    end
    add_index :pp_process_steps, [ :pp_process_id, :position ]

    # مصفوفة الصلاحيات الإجرائية — the operational authority matrix. One row per
    # decision taken inside the procedure.
    create_table :pp_process_authorities, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :pp_process, type: :uuid, null: false, foreign_key: true
      t.string :item, limit: 300
      t.string :decision, limit: 300
      t.integer :sort_order, null: false, default: 0
      t.timestamps
    end

    # Who holds which AuthorityLevel for that decision. `condition` carries what
    # the source documents smuggle into asterisked footnotes, so a qualifier on
    # an assignment is data rather than typography.
    create_table :pp_authority_assignments, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :pp_process_authority, type: :uuid, null: false, foreign_key: true
      t.string :level, limit: 20, null: false
      t.string :holder_title, limit: 250
      t.references :org_unit, type: :uuid, null: true, foreign_key: true
      t.string :condition, limit: 300
      t.integer :sort_order, null: false, default: 0
      t.timestamps
    end
    add_index :pp_authority_assignments, [ :pp_process_authority_id, :level ],
      name: "index_pp_authority_assignments_on_authority_and_level"
  end
end
