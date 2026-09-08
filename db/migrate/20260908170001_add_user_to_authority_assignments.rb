class AddUserToAuthorityAssignments < ActiveRecord::Migration[8.0]
  def change
    # A holder may be a person as well as a position. The principle that
    # authority attaches to the position is kept — a unit remains the usual
    # choice — but a company that names a person must be able to say so.
    add_reference :authority_assignments, :user, type: :uuid, null: true, foreign_key: true
  end
end
