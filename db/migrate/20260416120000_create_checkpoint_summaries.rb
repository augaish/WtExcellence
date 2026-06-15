class CreateCheckpointSummaries < ActiveRecord::Migration[8.0]
  def change
    create_table :checkpoint_summaries, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :tool_clause_id, null: false
      t.uuid :checklist_item_id, null: false
      t.bigint :tool_checkpoint_id, null: false
      t.uuid :company_id
      t.text :summary
      t.uuid :last_edited_by_user_id

      t.timestamps
    end

    add_index :checkpoint_summaries, :tool_clause_id
    add_index :checkpoint_summaries, :checklist_item_id
    add_index :checkpoint_summaries, :tool_checkpoint_id
    add_index :checkpoint_summaries, :company_id
    add_index :checkpoint_summaries,
              [:tool_clause_id, :checklist_item_id, :tool_checkpoint_id, :company_id],
              unique: true,
              name: "idx_checkpoint_summaries_unique_key"

    add_foreign_key :checkpoint_summaries, :tool_clauses
    add_foreign_key :checkpoint_summaries, :checklist_items
    add_foreign_key :checkpoint_summaries, :tool_checkpoints
    add_foreign_key :checkpoint_summaries, :companies
    add_foreign_key :checkpoint_summaries, :users, column: :last_edited_by_user_id
  end
end
