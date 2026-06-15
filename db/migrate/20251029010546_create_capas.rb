class CreateCapas < ActiveRecord::Migration[8.0]
  def change
    create_table :capas, id: :uuid do |t|
      t.string :title
      t.text :description
      t.string :source
      t.string :priority
      t.references :standard, null: true, foreign_key: true, type: :uuid

      t.timestamps
    end
  end
end
