# frozen_string_literal: true

class CreateNotifications < ActiveRecord::Migration[7.1]
  def change
    create_table :notifications, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :recipient, type: :uuid, null: false, foreign_key: { to_table: :users }
      t.string :kind, null: false, limit: 100
      t.string :title, limit: 500
      t.text :body
      t.string :link_path, limit: 500
      t.timestamptz :read_at
      t.string :source_type, limit: 100
      t.uuid :source_id
      t.jsonb :payload, default: {}

      t.timestamps
    end

    add_index :notifications, [ :recipient_id, :read_at ]
    add_index :notifications, :created_at
    add_index :notifications, [ :source_type, :source_id ]
  end
end
