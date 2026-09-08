class CreateGlossaryAndReferences < ActiveRecord::Migration[8.0]
  def change
    # Every governed document opens with التعريفات والاختصارات. Today each one
    # retypes its definitions, so the same term drifts between documents. Terms
    # live once per company and documents select from them.
    create_table :glossary_terms, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :company, type: :uuid, null: false, foreign_key: true
      t.string :term_en, limit: 250
      t.string :term_ar, limit: 250
      t.string :abbreviation, limit: 50
      t.text :definition_en
      t.text :definition_ar
      t.integer :sort_order, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    # The terms a given document prints, in the order it prints them.
    create_table :pp_record_terms, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :pp_record, type: :uuid, null: false, foreign_key: true
      t.references :glossary_term, type: :uuid, null: false, foreign_key: true
      t.integer :sort_order, null: false, default: 0
      t.timestamps
    end
    add_index :pp_record_terms, [ :pp_record_id, :glossary_term_id ], unique: true,
      name: "index_pp_record_terms_uniqueness"

    # The المراجع table. A reference is normally free text, but pointing it at an
    # ingested clause is what ties a policy to the standard it satisfies — the
    # link between the Standards library and the P&P module.
    create_table :pp_record_references, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :pp_record, type: :uuid, null: false, foreign_key: true
      t.references :clause, type: :uuid, null: true, foreign_key: true
      t.string :name, limit: 300
      t.string :source, limit: 300
      t.integer :sort_order, null: false, default: 0
      t.timestamps
    end
  end
end
