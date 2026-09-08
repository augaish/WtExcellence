class AddConformanceAndConsultation < ActiveRecord::Migration[8.0]
  def change
    # An authority keeps one identity across matrix versions, so two versions
    # can be compared row by row. Without it a diff can only guess which row
    # became which, and renaming an authority would read as a deletion plus an
    # addition.
    add_column :authorities, :stable_key, :string, limit: 64
    add_index :authorities, [ :company_id, :stable_key ]

    # The link that makes conformance checkable: the executive authority an
    # operational decision exercises. Optional, because an operational matrix
    # covers day-to-day decisions the executive matrix never mentions.
    add_reference :pp_process_authorities, :authority, type: :uuid, null: true, foreign_key: true

    # The consultation cycle, run today in a spreadsheet: 172 objections from
    # organizational units, each with a challenge, a proposal, an expected
    # impact and a ruling from Institutional Excellence.
    create_table :authority_consultations, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :matrix, type: :uuid, null: false, foreign_key: { to_table: :pp_records }
      t.references :authority, type: :uuid, null: true, foreign_key: true
      t.references :org_unit, type: :uuid, null: true, foreign_key: true
      t.references :raised_by, type: :uuid, null: true, foreign_key: { to_table: :users }

      t.text :challenge
      t.text :proposal
      t.text :expected_impact
      t.text :ruling
      t.string :status, limit: 20, null: false, default: "open"
      t.references :ruled_by, type: :uuid, null: true, foreign_key: { to_table: :users }
      t.datetime :ruled_at
      t.timestamps
    end
    add_index :authority_consultations, [ :matrix_id, :status ]
  end
end
