class DropToolStandards < ActiveRecord::Migration[8.0]
  def up
    return unless table_exists?(:tool_standards)

    # Remove foreign keys if they exist
    if foreign_key_exists?(:tool_standards, :tools)
      remove_foreign_key :tool_standards, :tools
    end
    if foreign_key_exists?(:tool_standards, :standards)
      remove_foreign_key :tool_standards, :standards
    end

    drop_table :tool_standards, if_exists: true
  end

  def down
    return if table_exists?(:tool_standards)

    create_table :tool_standards, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :tool_id, null: false
      t.uuid :standard_id, null: false
      t.datetime :created_at, null: false, default: -> { "now()" }
      t.datetime :updated_at, null: false, default: -> { "now()" }

      t.index [ :tool_id, :standard_id ], unique: true, name: "index_tool_standards_on_tool_id_and_standard_id"
      t.index [ :standard_id ], name: "index_tool_standards_on_standard_id"
      t.index [ :tool_id ], name: "index_tool_standards_on_tool_id"
    end

    add_foreign_key :tool_standards, :tools, column: :tool_id
    add_foreign_key :tool_standards, :standards
  end
end


