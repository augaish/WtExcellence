class CreateToolStandards < ActiveRecord::Migration[8.0]
  def change
    create_table :tool_standards, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :tool_id, null: false
      t.uuid :standard_id, null: false
      t.timestamps

      t.index [ :tool_id, :standard_id ], unique: true, name: "index_tool_standards_on_tool_id_and_standard_id"
      t.index :tool_id
      t.index :standard_id
    end

    add_foreign_key :tool_standards, :tools, column: :tool_id
    add_foreign_key :tool_standards, :standards
  end
end
