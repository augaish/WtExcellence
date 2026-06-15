class CreateStandardTranslations < ActiveRecord::Migration[8.0]
  def change
    create_table :standard_translations, id: :uuid do |t|
      t.references :standard, null: false, foreign_key: true, type: :uuid
      t.string :language_code, null: false, limit: 10
      t.string :name, null: false, limit: 255
      t.text :description

      t.timestamps
    end

    add_index :standard_translations, [ :standard_id, :language_code ], unique: true
    add_foreign_key :standard_translations, :languages, column: :language_code, primary_key: :code
  end
end
