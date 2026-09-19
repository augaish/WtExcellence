# While away, a person names who acts for them and for how long, so nobody
# shares a password.
class AddDelegationToUsers < ActiveRecord::Migration[8.0]
  def change
    add_reference :users, :delegate_user, type: :uuid, foreign_key: { to_table: :users }, null: true
    add_column :users, :delegate_from, :date
    add_column :users, :delegate_until, :date
  end
end
