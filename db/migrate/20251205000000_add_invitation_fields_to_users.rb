class AddInvitationFieldsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :invitation_token, :string
    add_column :users, :invitation_sent_at, :datetime
    add_column :users, :invitation_accepted_at, :datetime
    add_column :users, :invitation_expires_at, :datetime
    add_reference :users, :invited_by, foreign_key: { to_table: :users }, type: :uuid, null: true

    add_index :users, :invitation_token, unique: true
  end
end

