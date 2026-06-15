class CreateTools < ActiveRecord::Migration[8.0]
  def change
    create_table :tools do |t|
      t.string :name
      t.text :description

      t.timestamps
    end
    add_index :tools, :name, unique: true
  end
end
