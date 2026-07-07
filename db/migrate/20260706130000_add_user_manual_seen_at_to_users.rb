class AddUserManualSeenAtToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :user_manual_seen_at, :datetime
  end
end
