class CreateToolCheckpoints < ActiveRecord::Migration[8.0]
  def change
    create_table :tool_checkpoints do |t|
      t.references :tool, null: false, foreign_key: true
      t.string :name
      t.text :description
      t.integer :display_order

      t.timestamps
    end
  end
end
