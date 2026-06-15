class CreateActions < ActiveRecord::Migration[8.0]
  def change
    create_table :capa_actions, id: :uuid do |t|
      t.references :capa, null: false, foreign_key: true, type: :uuid
      t.string :title, null: false
      t.string :action_type, null: false
      t.string :status, null: false
      t.date :due_date
      t.text :notes

      t.timestamps
    end
  end
end
