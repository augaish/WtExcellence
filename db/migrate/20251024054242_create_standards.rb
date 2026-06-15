class CreateStandards < ActiveRecord::Migration[8.0]
  def change
    create_table :standards, id: :uuid do |t|
      t.string :code, null: false, limit: 100
      t.boolean :is_primary, default: false

      t.timestamps
    end

    add_index :standards, :code, unique: true
  end
end
