class AddAuditorApprovedStatus < ActiveRecord::Migration[8.0]
  def up
    # Add the new status value to the enum
    # The enum is stored as a string, so no schema change needed
    # Just documenting the new status value
    
    # Optionally, you can add a comment to document this
    execute <<-SQL
      COMMENT ON COLUMN tool_clause_subcheckpoint_assignments.status IS 
      'Status values: not_started, in_drafts, under_review, auditor_approved, approved, needs_changes';
    SQL
  end

  def down
    # Remove the comment if rolling back
    execute <<-SQL
      COMMENT ON COLUMN tool_clause_subcheckpoint_assignments.status IS 
      'Status values: not_started, in_drafts, under_review, approved, needs_changes';
    SQL
  end
end









