class AddClosureDetailsToRisks < ActiveRecord::Migration[8.0]
  def change
    # Closing a risk recorded nothing about why, who decided, or when. Existing
    # closed risks keep a null reason: the requirement applies to closures made
    # from here on, so historical records are not retro-fitted with invented
    # justifications.
    add_column :risks, :closure_reason, :text
    add_column :risks, :closed_at, :datetime
    add_column :risks, :closed_by_id, :uuid

    add_index :risks, :closed_by_id
  end
end
