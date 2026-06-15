class CreateLanguages < ActiveRecord::Migration[8.0]
  def change
    create_table :languages, id: :uuid do |t|
      t.string :code, null: false, limit: 10
      t.string :name, null: false, limit: 100
      t.string :direction, null: false, default: 'ltr', limit: 3

      t.timestamps
    end

    add_index :languages, :code, unique: true
  end
end
