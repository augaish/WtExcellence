class CreatePpDiagrams < ActiveRecord::Migration[8.0]
  # Phase 4: the Process Architect.
  #
  # A diagram is authored ELEMENT BY ELEMENT in a structured editor — never on a
  # freehand canvas — and the picture is generated from that structure. The
  # column names here deliberately match the evaluation contract in Phase 5
  # (type/title/performer/desc/input/output/trigger/scope/flow_label), so the
  # evaluator reads the model directly with no translation layer.
  def change
    create_table :pp_diagrams, id: :uuid do |t|
      t.references :company, null: false, foreign_key: true, type: :uuid
      # A diagram belongs to the record or the process it was opened from.
      t.references :owner, polymorphic: true, null: false, type: :uuid
      t.string :name, limit: 250

      # Process-level summary fields, captured once (not per element).
      t.text :trigger_text
      t.text :inputs_summary
      t.text :outputs_summary

      # Cached from the last evaluation so registers and widgets can show a
      # score without recomputing.
      t.integer :last_score
      t.datetime :last_evaluated_at

      t.timestamps
    end
    add_index :pp_diagrams, [ :owner_type, :owner_id, :created_at ],
      name: "index_pp_diagrams_on_owner_and_created"

    create_table :pp_diagram_elements, id: :uuid do |t|
      t.references :pp_diagram, null: false, foreign_key: true, type: :uuid
      t.integer :position, null: false, default: 0
      t.string :element_type, limit: 40, null: false
      t.string :title, limit: 300
      t.string :performer, limit: 200
      t.text :description
      t.text :input
      t.text :output
      t.text :trigger_text
      t.string :scope, limit: 20, null: false, default: "internal"
      t.string :flow_label, limit: 200

      t.timestamps
    end
    add_index :pp_diagram_elements, [ :pp_diagram_id, :position ]

    create_table :pp_diagram_flows, id: :uuid do |t|
      t.references :pp_diagram, null: false, foreign_key: true, type: :uuid
      t.references :from_element, null: false,
        foreign_key: { to_table: :pp_diagram_elements }, type: :uuid
      t.references :to_element, null: false,
        foreign_key: { to_table: :pp_diagram_elements }, type: :uuid
      t.string :kind, limit: 20, null: false, default: "sequence"
      t.string :label, limit: 200

      t.timestamps
    end
    add_index :pp_diagram_flows, [ :pp_diagram_id, :from_element_id, :to_element_id ],
      unique: true, name: "idx_pp_diagram_flows_unique"
  end
end
