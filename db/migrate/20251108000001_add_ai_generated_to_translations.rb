class AddAiGeneratedToTranslations < ActiveRecord::Migration[8.0]
  def change
    add_column :clause_translations, :ai_generated, :boolean, default: false
    add_index :clause_translations, :ai_generated

    add_column :checklist_item_translations, :ai_generated, :boolean, default: false
    add_index :checklist_item_translations, :ai_generated
  end
end
