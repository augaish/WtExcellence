class CreateAuditLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :audit_logs, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :actor_user, null: false, foreign_key: { to_table: :users }, type: :uuid
      t.references :company, null: false, foreign_key: true, type: :uuid
      t.string :action, null: false, limit: 200
      t.string :entity_type, limit: 100
      t.uuid :entity_id
      t.jsonb :payload_json
      t.column :created_at, :timestamptz, default: -> { "now()" }, null: false
    end

    # Note: actor_user_id and company_id indexes are automatically created by t.references
    add_index :audit_logs, :action
    add_index :audit_logs, [:entity_type, :entity_id]
    add_index :audit_logs, :created_at
  end
end

