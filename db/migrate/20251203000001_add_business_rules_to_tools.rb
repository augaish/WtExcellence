class AddBusinessRulesToTools < ActiveRecord::Migration[7.1]
  def change
    add_column :tools, :business_rules, :jsonb, default: {}
    add_index :tools, :business_rules, using: :gin
  end
end

