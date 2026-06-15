class CreateChecklistItemTranslations < ActiveRecord::Migration[8.0]
  def change
    create_table :checklist_item_translations, id: :uuid do |t|
      t.references :checklist_item, null: false, foreign_key: true, type: :uuid
      t.string :language_code, null: false, limit: 10
      t.text :text, null: false
      t.text :guidance

      t.timestamps
    end

    add_index :checklist_item_translations, [ :checklist_item_id, :language_code ], unique: true
    add_foreign_key :checklist_item_translations, :languages, column: :language_code, primary_key: :code
  end
end
