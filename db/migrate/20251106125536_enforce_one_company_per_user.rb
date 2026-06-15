class EnforceOneCompanyPerUser < ActiveRecord::Migration[8.0]
  def up
    # Remove any duplicate company_users (keep the first one for each user)
    # First, find duplicates and keep only the oldest record for each user
    execute <<-SQL
      DELETE FROM company_users
      WHERE id IN (
        SELECT id
        FROM (
          SELECT id,
                 ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY created_at ASC) as rn
          FROM company_users
        ) t
        WHERE t.rn > 1
      )
    SQL

    # Add unique index on user_id to enforce one company per user
    add_index :company_users, :user_id, unique: true, if_not_exists: true
  end

  def down
    remove_index :company_users, :user_id
  end
end
