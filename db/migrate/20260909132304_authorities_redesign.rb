# The Authorities & Delegations page as the product owner redrew it: no money
# bands (a limit is written on the authority), categories ordered by hand, a
# review round before a version is published, a Governance Manager who runs
# it, and operational authorities that hang off procedure steps.
class AuthoritiesRedesign < ActiveRecord::Migration[8.0]
  def change
    # Governance Managers: risk managers the company admin names.
    add_column :company_users, :gov_manager, :boolean, null: false, default: false

    # "Up to SAR 100,000" written on the authority, instead of bands.
    add_column :authorities, :limit_text, :string, limit: 250

    # Who was asked to look at a version before it is published, and what they said.
    create_table :authority_matrix_reviews, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :matrix, type: :uuid, null: false, foreign_key: { to_table: :pp_records }
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.uuid :requested_by_id
      t.datetime :requested_at, null: false
      t.string :decision, limit: 20
      t.text :comment
      t.datetime :decided_at
      t.timestamps
    end
    add_index :authority_matrix_reviews, [ :matrix_id, :user_id ], unique: true

    # Operational authorities belong to the procedure record and, when the
    # decision is one step's, to that step.
    add_reference :pp_process_authorities, :pp_record, type: :uuid, foreign_key: true
    add_reference :pp_process_authorities, :pp_process_step, type: :uuid, foreign_key: true
    change_column_null :pp_process_authorities, :pp_process_id, true
  end
end
