class CreateAiInstructions < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_instructions, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :company, null: false, foreign_key: true, type: :uuid
      t.string :title, null: false
      t.text :content_en
      t.text :content_ar
      t.boolean :active, null: false, default: true
      t.references :created_by, foreign_key: { to_table: :users }, type: :uuid
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :ai_instructions, :deleted_at
  end
end
