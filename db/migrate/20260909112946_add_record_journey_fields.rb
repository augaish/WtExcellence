# Each record type gets the fields its own journey asks for. Policies and forms
# gain a scope; procedures carry the procedure card that used to sit on the
# level-3 process; services carry the service card. Links between records
# (a procedure's related policies and forms, a service's participating units)
# are rows, not free text, so they can be followed.
class AddRecordJourneyFields < ActiveRecord::Migration[8.0]
  def change
    change_table :pp_records do |t|
      t.text :scope

      # Procedure card
      t.string :trigger_text, limit: 500
      t.text :inputs
      t.text :outputs
      t.uuid :predecessor_record_id
      t.uuid :successor_record_id
      t.string :frequency, limit: 20
      t.decimal :total_time_value, precision: 10, scale: 2
      t.string :total_time_unit, limit: 10
      t.string :automation_status, limit: 30
      t.text :technical_systems
      t.text :kpis
      t.integer :sequence_number

      # Service card
      t.string :service_type, limit: 20
      t.text :requirements
      t.text :beneficiaries
      t.string :delivery_period, limit: 250
      t.text :channels
      t.text :delivery_stages
    end
    add_foreign_key :pp_records, :pp_records, column: :predecessor_record_id, on_delete: :nullify
    add_foreign_key :pp_records, :pp_records, column: :successor_record_id, on_delete: :nullify

    create_table :pp_record_links, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :pp_record, type: :uuid, null: false, foreign_key: true
      t.references :linked_record, type: :uuid, null: false, foreign_key: { to_table: :pp_records }
      t.string :kind, limit: 30, null: false
      t.timestamps
    end
    add_index :pp_record_links, [ :pp_record_id, :linked_record_id, :kind ], unique: true, name: "index_pp_record_links_unique"

    create_table :pp_record_participants, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :pp_record, type: :uuid, null: false, foreign_key: true
      t.references :org_unit, type: :uuid, null: false, foreign_key: true
      t.timestamps
    end
    add_index :pp_record_participants, [ :pp_record_id, :org_unit_id ], unique: true
  end
end
