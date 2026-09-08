class CreateServiceLevelsAndDelegationNotices < ActiveRecord::Migration[8.0]
  def change
    # An agreement has two parties. The owning unit is the provider, already on
    # the record; this is the other side.
    add_column :pp_records, :counterparty, :string, limit: 250

    # The measurable commitments of a service level agreement. An SLA usually
    # carries several — availability, response, resolution — each with its own
    # target and its own way of being measured, so they are rows rather than
    # columns on the agreement.
    create_table :pp_service_levels, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :pp_record, type: :uuid, null: false, foreign_key: true
      t.string :service_name, limit: 250
      t.string :metric, limit: 30, null: false, default: "response_time"
      t.decimal :target_value, precision: 10, scale: 2
      t.string :target_unit, limit: 20
      t.text :measurement_method
      t.string :coverage, limit: 250
      t.text :escalation_path
      t.text :remedy
      t.integer :sort_order, null: false, default: 0
      t.timestamps
    end
    add_index :pp_service_levels, [ :pp_record_id, :sort_order ]

    # Stops one delegation being warned about twice for the same lapse, without
    # needing the job to remember what it has already sent.
    add_column :authority_delegations, :expiry_notified_at, :datetime
  end
end
