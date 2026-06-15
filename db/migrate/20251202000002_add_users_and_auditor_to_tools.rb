class AddUsersAndAuditorToTools < ActiveRecord::Migration[8.0]
  def change
    # Add auditor to tools (tools.id is bigint, users.id is uuid)
    add_reference :tools, :auditor, foreign_key: { to_table: :users }, type: :uuid, null: true

    # Create join table for tool users
    # tools.id is bigint, users.id is uuid
    create_table :tool_users do |t|
      t.bigint :tool_id, null: false
      t.uuid :user_id, null: false
      t.timestamps
    end

    add_foreign_key :tool_users, :tools
    add_foreign_key :tool_users, :users
    add_index :tool_users, [ :tool_id, :user_id ], unique: true
  end
end
