class CreateClauseTranslations < ActiveRecord::Migration[8.0]
  def change
    create_table :clause_translations, id: :uuid do |t|
      t.references :clause, null: false, foreign_key: true, type: :uuid
      t.string :language_code, null: false, limit: 10
      t.string :title, null: false, limit: 500
      t.text :summary
      t.text :body

      t.timestamps
    end

    add_index :clause_translations, [ :clause_id, :language_code ], unique: true
    add_foreign_key :clause_translations, :languages, column: :language_code, primary_key: :code
  end
end
