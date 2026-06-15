class RekeyAssessmentUsersToChecklistItem < ActiveRecord::Migration[8.0]
  def up
    # Existing contributor rows are scoped per tool_subcheckpoint_id, which
    # collided across checklist items when the index-clamp in the assessment
    # page mapped many items to the same subcheckpoint. Drop them and let
    # admins re-assign cleanly. Auditor rows have tool_subcheckpoint_id = nil
    # and are untouched.
    execute "DELETE FROM assessment_users WHERE role = 'contributor'"

    remove_index :assessment_users, name: "idx_assessment_users_unique"
    remove_index :assessment_users, :tool_subcheckpoint_id
    remove_foreign_key :assessment_users, column: :tool_subcheckpoint_id
    remove_column :assessment_users, :tool_subcheckpoint_id

    add_column :assessment_users, :checklist_item_id, :uuid
    add_index :assessment_users, :checklist_item_id
    add_index :assessment_users,
              [:assessment_id, :user_id, :checklist_item_id],
              unique: true,
              name: "idx_assessment_users_unique"
    add_foreign_key :assessment_users, :checklist_items, column: :checklist_item_id
  end

  def down
    remove_foreign_key :assessment_users, column: :checklist_item_id
    remove_index :assessment_users, name: "idx_assessment_users_unique"
    remove_index :assessment_users, :checklist_item_id
    remove_column :assessment_users, :checklist_item_id

    add_column :assessment_users, :tool_subcheckpoint_id, :bigint
    add_index :assessment_users, :tool_subcheckpoint_id
    add_index :assessment_users,
              [:assessment_id, :user_id, :tool_subcheckpoint_id],
              unique: true,
              name: "idx_assessment_users_unique"
    add_foreign_key :assessment_users, :tool_subcheckpoints, column: :tool_subcheckpoint_id
  end
end
