class AddModificationTrackingToTranslations < ActiveRecord::Migration[8.0]
  def change
    add_column :clause_translations, :last_modified_at, :datetime
    add_column :clause_translations, :source_updated_at, :datetime
    add_column :clause_translations, :needs_review, :boolean, default: false
    add_index :clause_translations, :needs_review

    add_column :checklist_item_translations, :last_modified_at, :datetime
    add_column :checklist_item_translations, :source_updated_at, :datetime
    add_column :checklist_item_translations, :needs_review, :boolean, default: false
    add_index :checklist_item_translations, :needs_review
  end
end
