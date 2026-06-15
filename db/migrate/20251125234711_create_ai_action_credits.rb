class CreateAiActionCredits < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_action_credits do |t|
      t.string :action_type, null: false
      t.integer :credit_cost, default: 0, null: false
      t.string :display_name, null: false

      t.timestamps
    end

    add_index :ai_action_credits, :action_type, unique: true
  end
end
