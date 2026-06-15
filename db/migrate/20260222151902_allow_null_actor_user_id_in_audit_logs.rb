class AllowNullActorUserIdInAuditLogs < ActiveRecord::Migration[8.0]
  def change
    change_column_null :audit_logs, :actor_user_id, true
    
    # Remove the existing foreign key
    remove_foreign_key :audit_logs, :users, column: :actor_user_id
    
    # Add the foreign key back with on_delete: :nullify
    add_foreign_key :audit_logs, :users, column: :actor_user_id, on_delete: :nullify
  end
end
