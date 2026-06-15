class CreateToolSubcheckpoints < ActiveRecord::Migration[8.0]
  def change
    create_table :tool_subcheckpoints do |t|
      t.references :tool_checkpoints, null: false, foreign_key: true
      t.string :name
      t.text :description
      t.string :scoring_type
      t.decimal :min_score
      t.decimal :max_score
      t.integer :display_order

      t.timestamps
    end
  end
end
