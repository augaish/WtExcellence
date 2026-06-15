class CreateQuestionnaires < ActiveRecord::Migration[8.0]
  def change
    create_table :questionnaires, id: :uuid do |t|
      t.uuid :capa_id, null: false
      t.text :question_1
      t.text :question_2
      t.text :question_3
      t.text :question_4
      t.text :question_5
      t.text :answer_1
      t.text :answer_2
      t.text :answer_3
      t.text :answer_4
      t.text :answer_5
      t.text :root_cause

      t.timestamps
    end

    add_foreign_key :questionnaires, :capas, column: :capa_id
    add_index :questionnaires, :capa_id, unique: true
  end
end
