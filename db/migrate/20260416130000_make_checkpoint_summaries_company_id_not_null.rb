class MakeCheckpointSummariesCompanyIdNotNull < ActiveRecord::Migration[8.0]
  def up
    # Remove any orphaned rows with null company_id before adding constraint
    execute "DELETE FROM checkpoint_summaries WHERE company_id IS NULL"
    change_column_null :checkpoint_summaries, :company_id, false
  end

  def down
    change_column_null :checkpoint_summaries, :company_id, true
  end
end
