class CreateCapaActivities < ActiveRecord::Migration[8.0]
  def change
    create_table :capa_activities, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :capa, null: false, foreign_key: true, type: :uuid
      t.string :activity_type, null: false
      t.text :description, null: false
      t.jsonb :metadata, default: {}
      t.references :performed_by, null: true, foreign_key: { to_table: :users }, type: :uuid

      t.timestamps
    end

    add_index :capa_activities, [ :capa_id, :created_at ]
    # Note: index on performed_by_id is automatically created by t.references
  end
end
