# Section 7 of Review 03: a service level agreement as its own capability.
# The provider is the owning unit; the other party is typed; each row says
# how it is compared, over what period, from what source and with what
# exclusions; and measured periods give attainment rather than a promise.
class SlaCapability < ActiveRecord::Migration[8.0]
  def change
    change_table :pp_records do |t|
      t.string :counterparty_kind, limit: 20            # internal_unit | customer | external_org
      t.uuid :counterparty_org_unit_id
    end
    add_foreign_key :pp_records, :org_units, column: :counterparty_org_unit_id, on_delete: :nullify

    change_table :pp_service_levels do |t|
      t.string :comparator, limit: 10                   # at_least | at_most
      t.string :measurement_period, limit: 20           # monthly | quarterly | annual
      t.string :measurement_source, limit: 250
      t.text :exclusions
      t.uuid :accountable_org_unit_id
      t.date :effective_from
      t.date :effective_to
    end
    add_foreign_key :pp_service_levels, :org_units, column: :accountable_org_unit_id, on_delete: :nullify

    create_table :sla_measurements, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :pp_service_level, type: :uuid, null: false, foreign_key: true
      t.date :period_start, null: false
      t.date :period_end, null: false
      t.decimal :actual_value, precision: 10, scale: 2, null: false
      t.text :source_note
      t.boolean :met, null: false, default: false
      t.uuid :recorded_by_id
      t.uuid :reviewed_by_id
      t.datetime :reviewed_at
      t.timestamps
    end
    add_index :sla_measurements, [ :pp_service_level_id, :period_start ], unique: true
    add_foreign_key :sla_measurements, :users, column: :recorded_by_id, on_delete: :nullify
    add_foreign_key :sla_measurements, :users, column: :reviewed_by_id, on_delete: :nullify

    add_column :customer_commitments, :sla_record_id, :uuid
    add_foreign_key :customer_commitments, :pp_records, column: :sla_record_id, on_delete: :nullify
  end
end
